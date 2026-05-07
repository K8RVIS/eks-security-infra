locals {
  vpn_route_table_ids = var.enable_vpn_private_api_access ? toset(var.vpn_route_table_ids) : toset([])
}

resource "aws_vpc_peering_connection" "vpn_to_eks" {
  count = var.enable_vpn_private_api_access ? 1 : 0

  vpc_id      = var.vpn_vpc_id
  peer_vpc_id = module.vpc.vpc_id
  auto_accept = true

  tags = merge(
    var.default_tags,
    {
      Name        = "${var.project_name}-${var.environment}-vpn-to-eks"
      Environment = var.environment
      ManagedBy   = "terraform"
      Purpose     = "eks-private-api-access"
    }
  )

  lifecycle {
    precondition {
      condition     = var.vpn_vpc_id != null && var.vpn_vpc_id != ""
      error_message = "vpn_vpc_id must be set when VPN private API access is enabled."
    }

    precondition {
      condition     = var.vpn_vpc_cidr != null && var.vpn_vpc_cidr != ""
      error_message = "vpn_vpc_cidr must be set when VPN private API access is enabled."
    }

    precondition {
      condition     = length(var.vpn_route_table_ids) > 0
      error_message = "At least one VPN route table ID must be set when VPN private API access is enabled."
    }
  }
}

resource "aws_vpc_peering_connection_options" "vpn_to_eks" {
  count = var.enable_vpn_private_api_access ? 1 : 0

  vpc_peering_connection_id = aws_vpc_peering_connection.vpn_to_eks[0].id

  requester {
    allow_remote_vpc_dns_resolution = true
  }

  accepter {
    allow_remote_vpc_dns_resolution = true
  }
}

resource "aws_route" "vpn_to_eks" {
  for_each = local.vpn_route_table_ids

  route_table_id            = each.value
  destination_cidr_block    = module.vpc.vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.vpn_to_eks[0].id
}

resource "aws_route" "eks_private_to_vpn" {
  count = var.enable_vpn_private_api_access ? 1 : 0

  route_table_id            = module.vpc.private_route_table_id
  destination_cidr_block    = var.vpn_vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.vpn_to_eks[0].id
}

resource "aws_vpc_security_group_ingress_rule" "allow_vpn_to_eks_private_api" {
  count = var.enable_vpn_private_api_access ? 1 : 0

  security_group_id = module.eks.cluster_security_group_id
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = var.vpn_vpc_cidr
  description       = "Allow VPN/self-hosted runner VPC to access the EKS private API endpoint"
}
