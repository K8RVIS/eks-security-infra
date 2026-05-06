output "vpc_id" {
  description = "VPC ID for the infra environment."
  value       = module.vpc.vpc_id
}

output "vpc_cidr" {
  description = "CIDR block for the infra VPC."
  value       = module.vpc.vpc_cidr
}

output "public_subnet_ids" {
  description = "Ordered list of public subnet IDs."
  value       = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  description = "Ordered list of private subnet IDs."
  value       = module.vpc.private_subnet_ids
}

output "fck_nat_instance_id" {
  description = "Instance ID of the fck-nat instance."
  value       = module.vpc.fck_nat_instance_id
}

output "fck_nat_ami_id" {
  description = "Automatically selected AMI ID for the fck-nat instance."
  value       = module.vpc.fck_nat_ami_id
}

output "cluster_name" {
  description = "Name of the infra EKS cluster."
  value       = module.eks.cluster_name
}

output "cluster_arn" {
  description = "ARN of the infra EKS cluster."
  value       = module.eks.cluster_arn
}

output "cluster_endpoint" {
  description = "API server endpoint of the infra EKS cluster."
  value       = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate authority data for the infra EKS cluster."
  value       = module.eks.cluster_certificate_authority_data
}

output "cluster_security_group_id" {
  description = "Cluster security group ID created by EKS."
  value       = module.eks.cluster_security_group_id
}

output "vpn_vpc_peering_connection_id" {
  description = "VPC peering connection ID between the infra VPC and VPN VPC."
  value       = module.vpn_peering.vpc_peering_connection_id
}

output "node_group_name" {
  description = "Name of the default infra EKS managed node group."
  value       = module.eks.node_group_name
}

output "node_group_arn" {
  description = "ARN of the default infra EKS managed node group."
  value       = module.eks.node_group_arn
}
