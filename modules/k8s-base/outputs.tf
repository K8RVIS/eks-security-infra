output "metrics_server_release_name" {
  description = "Helm release name for Metrics Server."
  value       = helm_release.metrics_server.name
}

output "aws_node_termination_handler_release_name" {
  description = "Helm release name for AWS Node Termination Handler."
  value       = helm_release.aws_node_termination_handler.name
}

output "aws_load_balancer_controller_release_name" {
  description = "Helm release name for AWS Load Balancer Controller."
  value       = helm_release.aws_load_balancer_controller.name
}

output "aws_load_balancer_controller_namespace" {
  description = "Namespace where AWS Load Balancer Controller is deployed."
  value       = helm_release.aws_load_balancer_controller.namespace
}

output "ingress_release_name" {
  description = "Helm release name for ingress-nginx."
  value       = helm_release.ingress_nginx.name
}

output "ingress_namespace" {
  description = "Namespace where ingress-nginx is deployed."
  value       = helm_release.ingress_nginx.namespace
}

output "ingress_service_name" {
  description = "Service name exposed by ingress-nginx."
  value       = "${helm_release.ingress_nginx.name}-controller"
}

output "external_secrets_release_name" {
  description = "Helm release name for External Secrets Operator."
  value       = helm_release.external_secrets.name
}

output "external_secrets_namespace" {
  description = "Namespace where External Secrets Operator is deployed."
  value       = helm_release.external_secrets.namespace
}

output "encrypted_storage_class_name" {
  description = "Encrypted gp3 StorageClass name for EBS-backed workload PVCs."
  value       = kubernetes_storage_class_v1.encrypted_gp3.metadata[0].name
}

output "prometheus_release_name" {
  description = "Helm release name for kube-prometheus-stack."
  value       = helm_release.kube_prometheus_stack.name
}

output "prometheus_namespace" {
  description = "Namespace where kube-prometheus-stack is deployed."
  value       = helm_release.kube_prometheus_stack.namespace
}
