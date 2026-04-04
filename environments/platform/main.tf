data "terraform_remote_state" "infra" {
  backend = "s3"

  config = {
    bucket = var.infra_state_bucket_name
    key    = var.infra_state_key
    region = var.infra_state_region
  }
}

data "aws_eks_cluster_auth" "infra" {
  name = data.terraform_remote_state.infra.outputs.cluster_name
}
