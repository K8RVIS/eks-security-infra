project_name = "eks-security-infra"
environment  = "dev"
aws_region   = "ap-northeast-2"

# Replace with the bootstrap tfstate bucket name before running plan/apply.
infra_state_bucket_name = "eks-security-infra-tfstate-example"
infra_state_key         = "infra/terraform.tfstate"
infra_state_region      = "ap-northeast-2"
