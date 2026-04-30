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

output "node_group_name" {
  description = "Name of the default infra EKS managed node group."
  value       = module.eks.node_group_name
}

output "node_group_arn" {
  description = "ARN of the default infra EKS managed node group."
  value       = module.eks.node_group_arn
}

output "ecr_repository_urls" {
  description = "Map of short repository name to full ECR repository URL."
  value       = module.ecr.repository_urls
}

output "ecr_registry_id" {
  description = "ECR registry ID (AWS account ID)."
  value       = module.ecr.registry_id
}

output "ecr_kms_key_arn" {
  description = "ARN of the KMS key used for ECR repository encryption."
  value       = module.ecr.kms_key_arn
}
