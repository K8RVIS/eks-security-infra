output "cluster_name" {
  description = "Name of the infra EKS cluster consumed by the platform stack."
  value       = data.terraform_remote_state.infra.outputs.cluster_name
}

output "cluster_endpoint" {
  description = "API server endpoint of the infra EKS cluster consumed by the platform stack."
  value       = data.terraform_remote_state.infra.outputs.cluster_endpoint
}

output "platform_state_ready" {
  description = "Whether the platform root is configured to consume the infra state."
  value       = true
}
