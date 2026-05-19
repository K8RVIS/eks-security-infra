output "cluster_name" {
  description = "Name of the EKS cluster."
  value       = aws_eks_cluster.this.name
}

output "cluster_arn" {
  description = "ARN of the EKS cluster."
  value       = aws_eks_cluster.this.arn
}

output "cluster_endpoint" {
  description = "API server endpoint of the EKS cluster."
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded cluster certificate authority data."
  value       = aws_eks_cluster.this.certificate_authority[0].data
}

output "cluster_security_group_id" {
  description = "Cluster security group created by EKS."
  value       = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

output "cluster_subnet_ids" {
  description = "Subnet IDs used by the EKS control plane."
  value       = var.cluster_subnet_ids
}

output "node_group_name" {
  description = "Name of the default managed node group."
  value       = aws_eks_node_group.this.node_group_name
}

output "node_group_arn" {
  description = "ARN of the default managed node group."
  value       = aws_eks_node_group.this.arn
}

output "node_group_role_arn" {
  description = "IAM role ARN used by the default managed node group."
  value       = aws_iam_role.node.arn
}

output "node_subnet_ids" {
  description = "Subnet IDs used by the default managed node group."
  value       = var.node_subnet_ids
}
