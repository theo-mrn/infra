terraform {
  backend "s3" {
    bucket         = "velero-k3s-cluster-backup"
    key            = "terraform/infra.tfstate"
    region         = "eu-west-3"
    encrypt        = true
  }
}
