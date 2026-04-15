variables {
  project_name        = "eks-secure-infra"
  environment         = "bootstrap"
  aws_region          = "ap-northeast-2"
  owner               = "K8RVIS"
  tfstate_bucket_name = "eks-secure-infra-tfstate"
  github_oidc_url     = "https://token.actions.githubusercontent.com"
  github_oidc_client_ids = [
    "sts.amazonaws.com",
  ]
  default_tags = {
    Repository = "eks-secure-infra"
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

  assert {
    condition     = aws_iam_openid_connect_provider.github_actions.url == var.github_oidc_url
    error_message = "Bootstrap must create the GitHub Actions OIDC provider with the configured issuer URL."
  }

  assert {
    condition     = contains(aws_iam_openid_connect_provider.github_actions.client_id_list, "sts.amazonaws.com")
    error_message = "Bootstrap must allow sts.amazonaws.com as an OIDC audience for GitHub Actions."
  }

  assert {
    condition     = output.github_oidc_provider_url == aws_iam_openid_connect_provider.github_actions.url
    error_message = "Bootstrap must expose the GitHub OIDC provider URL as an output."
  }
}
