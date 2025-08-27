#############################################
# locals
#############################################
locals {
  project_name          = var.name_prefix
  bucket_name_effective = coalesce(var.bucket_name, "${var.name_prefix}-bucket")

  # какую сеть используем: созданную или существующую
  vpc_network_id = var.create_network ? yandex_vpc_network.net[0].id : var.existing_network_id
}

#############################################
# VPC: network (optional), egress, route table, subnet, SG
#############################################

# создаём новую сеть только если нужно (иначе используем existing_network_id)
resource "yandex_vpc_network" "net" {
  count = var.create_network ? 1 : 0
  name  = "${local.project_name}-net"
}

# общий egress-шлюз (NAT) — создаём всегда, он "shared"
resource "yandex_vpc_gateway" "egress" {
  count = 1
  name  = "${local.project_name}-egress"
  shared_egress_gateway {}
}

# таблица маршрутов для выхода в интернет через egress
resource "yandex_vpc_route_table" "rt" {
  count      = 1
  network_id = local.vpc_network_id

  static_route {
    destination_prefix = "0.0.0.0/0"
    gateway_id         = yandex_vpc_gateway.egress[0].id
  }
}

# подсеть с привязкой к нашей RT (обеспечивает NAT)
resource "yandex_vpc_subnet" "subnet_a" {
  name           = "${local.project_name}-subnet-a"
  zone           = var.yc_zone
  network_id     = local.vpc_network_id
  v4_cidr_blocks = ["10.20.0.0/24"]
  route_table_id = yandex_vpc_route_table.rt[0].id
}

# security group для Data Proc
resource "yandex_vpc_security_group" "dp_sg" {
  name       = "${local.project_name}-dp-sg"
  network_id = local.vpc_network_id

  # внутренняя связность внутри SG
  ingress {
    protocol          = "ANY"
    from_port         = 0
    to_port           = 65535
    predefined_target = "self_security_group"
  }
  egress {
    protocol          = "ANY"
    from_port         = 0
    to_port           = 65535
    predefined_target = "self_security_group"
  }

  # исходящий HTTPS
  egress {
    protocol       = "TCP"
    port           = 443
    v4_cidr_blocks = ["0.0.0.0/0"]
    description    = "HTTPS"
  }

  # исходящий NTP
  egress {
    protocol       = "UDP"
    port           = 123
    v4_cidr_blocks = ["0.0.0.0/0"]
    description    = "NTP"
  }

  ingress {
    protocol       = "TCP"
    port           = 22
    v4_cidr_blocks = [var.admin_cidr]
    description    = "SSH from admin"
  }
}

#############################################
# Object Storage: публичный бакет
#############################################
resource "yandex_storage_bucket" "raw" {
  bucket    = local.bucket_name_effective
  folder_id = var.yc_folder_id

  anonymous_access_flags {
    read        = true
    list        = true
    config_read = true
  }

  force_destroy = true
}

#############################################
# IAM: Service Accounts + роли + S3 static keys
#############################################

# SA для Data Proc
resource "yandex_iam_service_account" "dp_sa" {
  name        = "${local.project_name}-dp-sa"
  description = "Service Account for Data Proc cluster"
}

# роли для SA кластера
resource "yandex_resourcemanager_folder_iam_member" "dp_sa_dataproc_agent" {
  folder_id = var.yc_folder_id
  role      = "dataproc.agent"
  member    = "serviceAccount:${yandex_iam_service_account.dp_sa.id}"
}

resource "yandex_resourcemanager_folder_iam_member" "dp_sa_dataproc_provisioner" {
  folder_id = var.yc_folder_id
  role      = "dataproc.provisioner"
  member    = "serviceAccount:${yandex_iam_service_account.dp_sa.id}"
}

resource "yandex_resourcemanager_folder_iam_member" "dp_sa_storage_editor" {
  folder_id = var.yc_folder_id
  role      = "storage.editor"
  member    = "serviceAccount:${yandex_iam_service_account.dp_sa.id}"
}

# SA для Object Storage (статические ключи для s3cmd) — опционально
resource "yandex_iam_service_account" "os_sa" {
  count       = var.create_static_keys ? 1 : 0
  name        = "${local.project_name}-os-sa"
  description = "Service Account to use static access keys for Object Storage"
}

resource "yandex_resourcemanager_folder_iam_member" "os_sa_storage_editor" {
  count     = var.create_static_keys ? 1 : 0
  folder_id = var.yc_folder_id
  role      = "storage.editor"
  member    = "serviceAccount:${yandex_iam_service_account.os_sa[0].id}"
}

resource "yandex_iam_service_account_static_access_key" "os_sa_keys" {
  count              = var.create_static_keys ? 1 : 0
  service_account_id = yandex_iam_service_account.os_sa[0].id
  description        = "Static access key for s3cmd"
}

#############################################
# Data Proc cluster (Spark + HDFS)
#############################################

# SSH public key (Terraform не разворачивает ~, используем pathexpand)
data "local_file" "ssh_pubkey" {
  filename = pathexpand(var.ssh_public_key_path)
}

resource "yandex_dataproc_cluster" "spark" {
  name               = "${local.project_name}-spark"
  description        = "OTUS homework — Spark cluster"
  bucket             = yandex_storage_bucket.raw.bucket
  service_account_id = yandex_iam_service_account.dp_sa.id
  zone_id            = var.yc_zone
  security_group_ids = [yandex_vpc_security_group.dp_sg.id]
  ui_proxy           = true
  environment        = "PRODUCTION"

  cluster_config {
    version_id = var.dataproc_version_id

    hadoop {
      services = ["HDFS", "YARN", "SPARK", "MAPREDUCE", "HIVE", "ZEPPELIN"]

      properties = {
        "core:fs.s3a.endpoint"          = "storage.yandexcloud.net"
        "core:fs.s3a.path.style.access" = "true"
      }

      ssh_public_keys = [data.local_file.ssh_pubkey.content]
    }

    # ---------- MASTER ----------
    subcluster_spec {
      name             = "master"
      role             = "MASTERNODE"
      subnet_id        = yandex_vpc_subnet.subnet_a.id
      hosts_count      = 1
      assign_public_ip = true

      resources {
        resource_preset_id = var.master_host_class # напр. "s3-c2-m8"
        disk_type_id       = "network-ssd"
        disk_size          = var.master_disk_gb # 40
      }
    }

    # ---------- DATA ----------
    subcluster_spec {
      name             = "data"
      role             = "DATANODE"
      subnet_id        = yandex_vpc_subnet.subnet_a.id
      hosts_count      = var.data_hosts_count # 3
      assign_public_ip = true

      resources {
        resource_preset_id = var.data_host_class # напр. "s3-c4-m16"
        disk_type_id       = "network-ssd"
        disk_size          = var.data_disk_gb # 128
      }
    }
  }

  depends_on = [
    yandex_resourcemanager_folder_iam_member.dp_sa_dataproc_agent,
    yandex_resourcemanager_folder_iam_member.dp_sa_dataproc_provisioner,
    yandex_resourcemanager_folder_iam_member.dp_sa_storage_editor
  ]
}