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

output "metrics_server_release_name" {
  description = "Helm release name for Metrics Server."
  value       = module.k8s_base.metrics_server_release_name
}

output "aws_node_termination_handler_release_name" {
  description = "Helm release name for AWS Node Termination Handler."
  value       = module.k8s_base.aws_node_termination_handler_release_name
}

output "ingress_release_name" {
  description = "Helm release name for ingress-nginx."
  value       = module.k8s_base.ingress_release_name
}

output "ingress_namespace" {
  description = "Namespace where ingress-nginx is deployed."
  value       = module.k8s_base.ingress_namespace
}

output "ingress_service_name" {
  description = "Service name exposed by ingress-nginx."
  value       = module.k8s_base.ingress_service_name
}

output "team_namespace_names" {
  description = "Created team namespace names."
  value       = module.namespaces.namespace_names
}

output "argocd_release_name" {
  description = "Helm release name for ArgoCD."
  value       = module.argocd.release_name
}

output "argocd_namespace" {
  description = "Namespace where ArgoCD is deployed."
  value       = module.argocd.namespace
}

output "argocd_server_service_name" {
  description = "Service name exposed by the ArgoCD server."
  value       = module.argocd.argocd_server_service_name
}

output "argocd_application_names" {
  description = "Generated team ArgoCD application names."
  value       = module.argocd.application_names
}
