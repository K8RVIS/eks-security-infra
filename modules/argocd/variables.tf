variable "helm_release_timeout_seconds" {
  description = "Timeout in seconds applied to the ArgoCD helm release."
  type        = number
  default     = 600
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
  description = "Team namespaces and matching ArgoCD application names."
  type        = list(string)
  default     = ["team-a", "team-b", "team-c", "team-d"]
}
