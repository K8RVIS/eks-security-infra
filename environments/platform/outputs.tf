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

output "acm_dns_validation_record_names" {
  description = "Cloudflare-managed ACM DNS validation record names."
  value       = [for record in cloudflare_record.acm_dns_validation : record.name]
}

output "metrics_server_release_name" {
  description = "Helm release name for Metrics Server."
  value       = module.k8s_base.metrics_server_release_name
}

output "aws_node_termination_handler_release_name" {
  description = "Helm release name for AWS Node Termination Handler."
  value       = module.k8s_base.aws_node_termination_handler_release_name
}

output "aws_load_balancer_controller_release_name" {
  description = "Helm release name for AWS Load Balancer Controller."
  value       = module.k8s_base.aws_load_balancer_controller_release_name
}

output "aws_load_balancer_controller_role_arn" {
  description = "IAM role ARN associated with AWS Load Balancer Controller through EKS Pod Identity."
  value       = aws_iam_role.aws_load_balancer_controller.arn
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

output "external_secrets_release_name" {
  description = "Helm release name for External Secrets Operator."
  value       = module.k8s_base.external_secrets_release_name
}

output "external_secrets_namespace" {
  description = "Namespace where External Secrets Operator is deployed."
  value       = module.k8s_base.external_secrets_namespace
}

output "external_secrets_role_arn" {
  description = "IAM role ARN associated with the External Secrets Operator service account."
  value       = aws_iam_role.external_secrets.arn
}

output "encrypted_storage_class_name" {
  description = "Encrypted gp3 StorageClass name for EBS-backed workload PVCs."
  value       = module.k8s_base.encrypted_storage_class_name
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
