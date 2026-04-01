variables {
  project_name        = "eks-security-infra"
  environment         = "bootstrap"
  aws_region          = "ap-northeast-2"
  owner               = "K8RVIS"
  tfstate_bucket_name = "eks-security-infra-tfstate-example"
  default_tags = {
    Repository = "eks-security-infra"
    ManagedBy  = "terraform"
  }
}

run "plan_creates_hardened_tfstate_bucket" {
  command = plan

  assert {
    condition     = aws_s3_bucket.tfstate.bucket == var.tfstate_bucket_name
    error_message = "tfstate bucket name must match the configured bucket name."
  }

  assert {
    condition     = aws_s3_bucket_versioning.tfstate.versioning_configuration[0].status == "Enabled"
    error_message = "tfstate bucket must enable versioning."
  }

  assert {
    condition     = aws_s3_bucket_public_access_block.tfstate.block_public_acls && aws_s3_bucket_public_access_block.tfstate.block_public_policy
    error_message = "tfstate bucket must block public access."
  }
}
