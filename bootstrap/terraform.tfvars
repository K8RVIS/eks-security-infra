project_name = "eks-secure-infra"
environment  = "bootstrap"
aws_region   = "ap-northeast-2"
owner        = "K8RVIS"

# Replace with a globally unique bucket name before running terraform apply.
tfstate_bucket_name = "eks-secure-infra-tfstate"

github_oidc_url = "https://token.actions.githubusercontent.com"

github_oidc_client_ids = [
  "sts.amazonaws.com",
]

default_tags = {
  Repository = "eks-secure-infra"
  ManagedBy  = "terraform"
}
