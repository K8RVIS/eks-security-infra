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
