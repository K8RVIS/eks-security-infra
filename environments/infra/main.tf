module "vpc" {
  source = "../../modules/vpc"

  project_name          = var.project_name
  environment           = var.environment
  aws_region            = var.aws_region
  owner                 = var.owner
  vpc_cidr              = var.vpc_cidr
  availability_zones    = var.availability_zones
  public_subnet_cidrs   = var.public_subnet_cidrs
  private_subnet_cidrs  = var.private_subnet_cidrs
  fck_nat_instance_type = var.fck_nat_instance_type
  default_tags          = var.default_tags
}

module "eks" {
  source = "../../modules/eks"

  project_name                          = var.project_name
  environment                           = var.environment
  owner                                 = var.owner
  cluster_subnet_ids                    = module.vpc.private_subnet_ids
  node_subnet_ids                       = module.vpc.public_subnet_ids
  cluster_private_endpoint_access_cidrs = var.cluster_private_endpoint_access_cidrs
  kubernetes_version                    = var.kubernetes_version
  node_ami_type                         = var.node_ami_type
  node_group                            = var.node_group
  default_tags                          = var.default_tags
}
