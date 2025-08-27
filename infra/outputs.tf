output "bucket_name" {
  value       = yandex_storage_bucket.raw.bucket
  description = "Имя публичного бакета"
}

output "bucket_public_url" {
  value       = "https://${yandex_storage_bucket.raw.bucket}.storage.yandexcloud.net/"
  description = "Публичный URL бакета"
}

output "dp_cluster_id" {
  value       = yandex_dataproc_cluster.spark.id
  description = "ID кластера Data Proc"
}

output "s3_access_key_id" {
  value       = try(yandex_iam_service_account_static_access_key.os_sa_keys[0].access_key, null)
  description = "S3 Access Key ID (для s3cmd)"
  sensitive   = true
}

output "s3_secret_access_key" {
  value       = try(yandex_iam_service_account_static_access_key.os_sa_keys[0].secret_key, null)
  description = "S3 Secret Access Key (для s3cmd)"
  sensitive   = true
}