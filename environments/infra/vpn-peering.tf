data "aws_route_tables" "vpn" {
  vpc_id = var.vpn_vpc_id
}

module "vpn_peering" {
  source = "../../modules/vpc-peering"

  project_name = var.project_name
  environment  = var.environment
  owner        = var.owner

  requester_vpc_id          = module.vpc.vpc_id
  requester_vpc_cidr        = module.vpc.vpc_cidr
  requester_route_table_ids = [module.vpc.private_route_table_id]

  accepter_vpc_id          = var.vpn_vpc_id
  accepter_vpc_cidr        = var.vpn_vpc_cidr
  accepter_route_table_ids = data.aws_route_tables.vpn.ids

  default_tags = var.default_tags
}
