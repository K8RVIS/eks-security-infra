variable "helm_release_timeout_seconds" {
  description = "Timeout in seconds applied to the Falco helm release."
  type        = number
  default     = 600
}

variable "falco_namespace" {
  description = "Namespace used for the Falco release."
  type        = string
  default     = "falco"
}

variable "falco_chart_version" {
  description = "Pinned chart version for Falco."
  type        = string
  default     = "8.0.5"
}
