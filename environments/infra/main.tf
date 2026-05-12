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
  node_subnet_ids                       = module.vpc.private_subnet_ids
  cluster_private_endpoint_access_cidrs = var.cluster_private_endpoint_access_cidrs
  kubernetes_version                    = var.kubernetes_version
  node_ami_type                         = var.node_ami_type
  node_group                            = var.node_group
  default_tags                          = var.default_tags

  authentication_mode = "API_AND_CONFIG_MAP"
  access_entries = {
  for name, arn in var.user_iam_arn : name => {
    principal_arn = arn
    policy_associations = {
      admin = {
        policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
        access_scope = {
          type = "cluster"
        }
      }
    }
  }
  if trimspace(arn) != ""
}
}
module "ecr" {
  source = "../../modules/ecr"

  project_name         = var.project_name
  environment          = var.environment
  owner                = var.owner
  repository_names     = var.ecr_repository_names
  max_image_count      = var.ecr_max_image_count
  untagged_expiry_days = var.ecr_untagged_expiry_days
  default_tags         = var.default_tags
}

module "workload_s3" {
  source = "../../modules/workload-s3"

  project_name  = var.project_name
  environment   = var.environment
  owner         = var.owner
  bucket_suffix = var.workload_s3_bucket_suffix
  default_tags  = var.default_tags
}
