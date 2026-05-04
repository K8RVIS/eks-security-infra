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
