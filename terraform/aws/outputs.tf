output "bucket_name" {
  value = aws_s3_bucket.velero.bucket
}

output "bucket_region" {
  value = var.aws_region
}

output "velero_access_key_id" {
  value     = aws_iam_access_key.velero.id
  sensitive = true
}

output "velero_secret_access_key" {
  value     = aws_iam_access_key.velero.secret
  sensitive = true
}
