terraform {
  backend "s3" {
    bucket  = "eks-secure-infra-tfstate"
    key     = "infra/terraform.tfstate"
    region  = "ap-northeast-2"
    profile = "team-b"
    #use_lockfile = true
  }
}
