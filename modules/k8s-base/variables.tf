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
  description = "Pre-created IRSA service account name used by AWS Load Balancer Controller."
  type        = string
  default     = "aws-load-balancer-controller"
}

variable "aws_load_balancer_controller_chart_version" {
  description = "Pinned chart version for AWS Load Balancer Controller."
  type        = string
  default     = "3.2.2"
}

variable "external_dns_enabled" {
  description = "Whether to deploy ExternalDNS."
  type        = bool
  default     = false
}

variable "external_dns_namespace" {
  description = "Namespace used for the ExternalDNS release."
  type        = string
  default     = "kube-system"
}

variable "external_dns_chart_version" {
  description = "Pinned chart version for ExternalDNS."
  type        = string
  default     = "1.20.0"
}

variable "external_dns_domain_filters" {
  description = "Domain suffixes ExternalDNS is allowed to manage."
  type        = list(string)
  default     = []
}

variable "external_dns_txt_owner_id" {
  description = "TXT registry owner ID used by ExternalDNS."
  type        = string
  default     = "eks-secure-infra"
}

variable "external_dns_policy" {
  description = "ExternalDNS synchronization policy."
  type        = string
  default     = "upsert-only"
}

variable "external_dns_cloudflare_api_token_secret_name" {
  description = "Kubernetes Secret name that stores the Cloudflare API token for ExternalDNS."
  type        = string
  default     = "external-dns-cloudflare"
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
