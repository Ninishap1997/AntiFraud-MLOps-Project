variable "yc_token" {
  type      = string
  sensitive = true
}

variable "yc_cloud_id" {
  type = string
}

variable "yc_folder_id" {
  type = string
}

variable "yc_zone" {
  type    = string
  default = "ru-central1-a"
}

variable "bucket_name" {
  type        = string
  description = "Имя публичного бакета Object Storage."
  default     = null
}

variable "ssh_public_key_path" {
  type        = string
  description = "Путь к публичному SSH ключу"
  default     = "~/.ssh/id_rsa.pub"
}

variable "create_static_keys" {
  type        = bool
  description = "Создавать ли SA и статические ключи для Object Storage"
  default     = true
}

variable "name_prefix" {
  type        = string
  description = "Префикс имён ресурсов"
  default     = "otus"
}

variable "master_host_class" {
  type    = string
  default = "s3-c2-m8"
}

variable "master_disk_gb" {
  type    = number
  default = 40
}

variable "data_host_class" {
  type    = string
  default = "s3-c4-m16"
}

variable "data_hosts_count" {
  type    = number
  default = 3
}

variable "data_disk_gb" {
  type    = number
  default = 128
}

variable "dataproc_version_id" {
  type    = string
  default = "2.0"
}

variable "yc_image_id" {
  type        = string
  description = "На будущее. Здесь не используется."
  default     = null
}

variable "create_network" {
  type        = bool
  description = "Создавать новую VPC сеть? Если false — будет использоваться existing_network_id"
  default     = true
}

variable "existing_network_id" {
  type        = string
  description = "ID уже существующей VPC сети (если create_network = false)"
  default     = null
}

variable "admin_cidr" {
  type = string
}