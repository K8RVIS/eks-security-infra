variable "project_name" {
  description = "Project identifier used in tags and naming."
  type        = string
}

variable "environment" {
  description = "Environment name for the platform stack."
  type        = string
}

variable "aws_region" {
  description = "AWS region for the platform stack."
  type        = string
}

variable "infra_state_bucket_name" {
  description = "S3 bucket name that stores the infra Terraform state."
  type        = string
}

variable "infra_state_key" {
  description = "S3 object key for the infra Terraform state."
  type        = string
  default     = "infra/terraform.tfstate"
}

variable "infra_state_region" {
  description = "AWS region of the S3 bucket that stores the infra Terraform state."
  type        = string
}

variable "helm_release_timeout_seconds" {
  description = "Timeout in seconds applied to each addon helm release."
  type        = number
  default     = 600
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
  description = "Pinned chart version for AWS Node Termination Handler. Set to null to use the repository default."
  type        = string
  default     = null
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

variable "argocd_namespace" {
  description = "Namespace used for the ArgoCD installation."
  type        = string
  default     = "argocd"
}

variable "argocd_chart_version" {
  description = "Pinned chart version for ArgoCD."
  type        = string
  default     = "9.4.17"
}

variable "argocd_apps_chart_version" {
  description = "Pinned chart version for argocd-apps."
  type        = string
  default     = "2.0.3"
}

variable "argocd_project_name" {
  description = "ArgoCD project name used by generated team applications."
  type        = string
  default     = "default"
}

variable "gitops_repo_url" {
  description = "Git repository URL that ArgoCD applications will watch."
  type        = string
  default     = "https://github.com/K8RVIS/eks-secure-infra.git"
}

variable "gitops_target_revision" {
  description = "Git revision used by generated ArgoCD applications."
  type        = string
  default     = "main"
}

variable "gitops_applications_base_path" {
  description = "Base path inside the GitOps repository for team application overlays."
  type        = string
  default     = "manifests/overlays"
}

variable "team_names" {
  description = "Team namespace names and matching ArgoCD application names."
  type        = list(string)
  default     = ["team-a", "team-b", "team-c", "team-d"]
}

variable "ingress_lb_acm_certificate_arn" {
  description = "ACM certificate ARN used by the ingress-nginx AWS load balancer TLS listener."
  type        = string
}
