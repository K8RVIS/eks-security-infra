mock_provider "aws" {
  override_during = plan
}

variables {
  project_name = "eks-secure-infra"
  environment  = "dev"
  owner        = "K8RVIS"

  requester_vpc_id          = "vpc-eks"
  requester_vpc_cidr        = "10.0.0.0/16"
  requester_route_table_ids = ["rtb-eks-private"]

  accepter_vpc_id          = "vpc-vpn"
  accepter_vpc_cidr        = "172.31.0.0/16"
  accepter_route_table_ids = ["rtb-vpn-a", "rtb-vpn-b"]

  default_tags = {
    Repository = "eks-secure-infra"
    ManagedBy  = "terraform"
  }
}

run "creates_bidirectional_vpc_peering_routes" {
  command = plan

  assert {
    condition     = aws_vpc_peering_connection.this.vpc_id == var.requester_vpc_id && aws_vpc_peering_connection.this.peer_vpc_id == var.accepter_vpc_id
    error_message = "VPC peering must connect the requester EKS VPC to the accepter VPN VPC."
  }

  assert {
    condition     = aws_vpc_peering_connection.this.auto_accept == true
    error_message = "Same-account VPN peering must be auto-accepted."
  }

  assert {
    condition     = aws_route.requester_to_accepter["rtb-eks-private"].route_table_id == "rtb-eks-private" && aws_route.requester_to_accepter["rtb-eks-private"].destination_cidr_block == "172.31.0.0/16"
    error_message = "The requester route table must route VPN VPC CIDR through the peering connection."
  }

  assert {
    condition     = aws_route.accepter_to_requester["rtb-vpn-a"].route_table_id == "rtb-vpn-a" && aws_route.accepter_to_requester["rtb-vpn-a"].destination_cidr_block == "10.0.0.0/16"
    error_message = "Each VPN route table must route EKS VPC CIDR through the peering connection."
  }

  assert {
    condition     = aws_vpc_peering_connection_options.this.requester[0].allow_remote_vpc_dns_resolution && aws_vpc_peering_connection_options.this.accepter[0].allow_remote_vpc_dns_resolution
    error_message = "VPC peering must allow remote VPC DNS resolution in both directions."
  }
}
