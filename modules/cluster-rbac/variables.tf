variable "admin_sa_name" {
  description = "Name of the admin service account"
  type        = string
  default     = "admin-sa"
}

variable "admin_sa_namespace" {
  description = "Namespace where the admin service account resides"
  type        = string
  default     = "team-dev"
}

variable "api_sa_name" {
  description = "Name of the API service account for health checks"
  type        = string
  default     = "api-workload"
}