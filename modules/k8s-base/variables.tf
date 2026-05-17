variable "helm_release_timeout_seconds" {
  description = "Timeout in seconds applied to each addon helm release."
  type        = number
  default     = 600
}

variable "aws_region" {
  description = "AWS region where the EKS cluster runs."
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name used by cluster-aware add-ons."
  type        = string
}

variable "vpc_id" {
  description = "VPC ID used by AWS Load Balancer Controller."
  type        = string
}

variable "metrics_server_namespace" {
  description = "Namespace used for the Metrics Server release."
  type        = string
  default     = "kube-system"
}

variable "metrics_server_chart_version" {
  description = "Pinned chart version for Metrics Server."
  type        = string
  default     = "3.13.0"
}

variable "aws_node_termination_handler_namespace" {
  description = "Namespace used for the AWS Node Termination Handler release."
  type        = string
  default     = "kube-system"
}

variable "aws_node_termination_handler_chart" {
  description = "Chart name for the AWS Node Termination Handler OCI repository."
  type        = string
  default     = "aws-node-termination-handler"
}

variable "aws_node_termination_handler_chart_version" {
  description = "Pinned chart version for AWS Node Termination Handler. Set to null to follow the repository default."
  type        = string
  default     = null
}

variable "aws_load_balancer_controller_namespace" {
  description = "Namespace used for the AWS Load Balancer Controller release."
  type        = string
  default     = "kube-system"
}

variable "aws_load_balancer_controller_service_account_name" {
  description = "Pre-created service account name used by AWS Load Balancer Controller."
  type        = string
  default     = "aws-load-balancer-controller"
}

variable "aws_load_balancer_controller_chart_version" {
  description = "Pinned chart version for AWS Load Balancer Controller."
  type        = string
  default     = "3.2.2"
}

variable "ingress_nginx_namespace" {
  description = "Namespace used for the ingress-nginx release."
  type        = string
  default     = "ingress-nginx"
}

variable "ingress_nginx_chart_version" {
  description = "Pinned chart version for ingress-nginx."
  type        = string
  default     = "4.14.1"
}

variable "external_secrets_namespace" {
  description = "Namespace used for the External Secrets Operator release."
  type        = string
  default     = "external-secrets"
}

variable "external_secrets_chart_version" {
  description = "Pinned chart version for External Secrets Operator. Set to null to use the repository default."
  type        = string
  default     = null
}

variable "external_secrets_service_account_name" {
  description = "ServiceAccount name used by External Secrets Operator."
  type        = string
  default     = "external-secrets"
}

variable "prometheus_namespace" {
  description = "Namespace used for the kube-prometheus-stack release."
  type        = string
  default     = "monitoring"
}

variable "prometheus_chart_version" {
  description = "Pinned chart version for kube-prometheus-stack."
  type        = string
  default     = "70.4.2"
}

variable "grafana_admin_password" {
  description = "Grafana admin password. Set via tfvars or environment variable (TF_VAR_grafana_admin_password)."
  type        = string
  sensitive   = true
}
