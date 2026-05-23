variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-west-3" # Paris
}

variable "bucket_name" {
  description = "S3 bucket name for Velero backups"
  type        = string
  default     = "velero-k3s-cluster-backup"
}
