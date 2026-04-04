output "release_name" {
  description = "Helm release name for ArgoCD."
  value       = helm_release.argocd.name
}

output "namespace" {
  description = "Namespace where ArgoCD is deployed."
  value       = helm_release.argocd.namespace
}

output "argocd_server_service_name" {
  description = "Service name exposed by the ArgoCD server."
  value       = "${helm_release.argocd.name}-server"
}

output "application_names" {
  description = "Names of generated team ArgoCD applications."
  value       = sort(keys(local.team_applications))
}
