project_name = "eks-security-infra"
environment  = "bootstrap"
aws_region   = "ap-northeast-2"
owner        = "K8RVIS"

# Replace with a globally unique bucket name before running terraform apply.
tfstate_bucket_name = "eks-security-infra-tfstate-example"

default_tags = {
  Repository = "eks-security-infra"
  ManagedBy  = "terraform"
}
