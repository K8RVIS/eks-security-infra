output "metrics_server_release_name" {
  description = "Helm release name for Metrics Server."
  value       = helm_release.metrics_server.name
}

output "aws_node_termination_handler_release_name" {
  description = "Helm release name for AWS Node Termination Handler."
  value       = helm_release.aws_node_termination_handler.name
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
