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

output "fck_nat_subnet_id" {
  description = "Subnet ID where the fck-nat instance is placed."
  value       = module.vpc.fck_nat_subnet_id
}

output "fck_nat_primary_network_interface_id" {
  description = "Primary network interface ID of the fck-nat instance."
  value       = module.vpc.fck_nat_primary_network_interface_id
}

output "fck_nat_ami_id" {
  description = "Automatically selected AMI ID for the fck-nat instance."
  value       = module.vpc.fck_nat_ami_id
}

output "private_default_route_network_interface_id" {
  description = "Network interface ID targeted by the private default route."
  value       = module.vpc.private_default_route_network_interface_id
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

output "cluster_subnet_ids" {
  description = "Subnet IDs used by the infra EKS control plane."
  value       = module.eks.cluster_subnet_ids
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

output "node_subnet_ids" {
  description = "Subnet IDs used by the default infra EKS managed node group."
  value       = module.eks.node_subnet_ids
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

output "break_glass_role_arn" {
  description = "ARN of the EKS break-glass IAM role."
  value       = var.break_glass_enabled ? aws_iam_role.break_glass[0].arn : null
}

output "break_glass_alert_topic_arn" {
  description = "ARN of the SNS topic used for break-glass and high-risk Kubernetes API alerts."
  value       = var.break_glass_enabled ? aws_sns_topic.break_glass_alerts[0].arn : null
}

output "eks_control_plane_log_group_name" {
  description = "CloudWatch Logs group name for EKS control plane logs."
  value       = aws_cloudwatch_log_group.eks_cluster.name
}

output "break_glass_jit_state_table_name" {
  description = "DynamoDB table that stores break-glass JIT grant state."
  value       = var.break_glass_enabled ? aws_dynamodb_table.break_glass_grants[0].name : null
}

output "break_glass_scheduler_group_name" {
  description = "EventBridge Scheduler group used for break-glass automatic revocation."
  value       = var.break_glass_enabled ? aws_scheduler_schedule_group.break_glass[0].name : null
}

output "break_glass_scheduler_role_arn" {
  description = "IAM role ARN used by EventBridge Scheduler to invoke the revoker Lambda."
  value       = var.break_glass_enabled ? aws_iam_role.break_glass_scheduler[0].arn : null
}

output "break_glass_revoker_lambda_arn" {
  description = "Lambda ARN that revokes expired break-glass JIT grants."
  value       = var.break_glass_enabled ? aws_lambda_function.break_glass_revoker[0].arn : null
}
