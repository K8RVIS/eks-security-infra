project_name = "eks-secure-infra"
environment  = "dev"
aws_region   = "ap-northeast-2"
owner        = "K8RVIS"

vpc_cidr = "10.0.0.0/16"

availability_zones = [
  "ap-northeast-2a",
  "ap-northeast-2c",
]

public_subnet_cidrs = [
  "10.0.1.0/24",
  "10.0.2.0/24",
]

private_subnet_cidrs = [
  "10.0.10.0/24",
  "10.0.20.0/24",
]

cluster_public_access_cidrs = [
  "13.125.215.119/32",
]

fck_nat_instance_type = "t4g.nano"

default_tags = {
  Repository = "eks-secure-infra"
  ManagedBy  = "terraform"
}

kubernetes_version = "1.34"

node_ami_type = "AL2023_ARM_64_STANDARD"

node_group = {
  instance_types = ["t4g.medium", "t4g.large", "m7g.large", "c7g.large"]
  desired_size   = 3
  min_size       = 2
  max_size       = 4
  disk_size_gb   = 20
}
user_iam_arn= {
  teamc_user="arn:aws:iam::357542025037:role/aws-reserved/sso.amazonaws.com/ap-northeast-2/AWSReservedSSO_AdministratorAccess_3a39e04d118e4347"
}
