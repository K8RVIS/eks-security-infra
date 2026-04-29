variable "project_name" {
  description = "Project identifier used in namespace labels."
  type        = string
}

variable "team_names" {
  description = "Team namespace names to create."
  type        = list(string)
  default     = ["team-a", "team-b", "team-c", "team-d"]
}

variable "secret_enabled_teams" {
  description = "Team namespaces where app-secrets Kubernetes Secret will be created."
  type        = list(string)
  default     = []
}

variable "redis_password" {
  description = "Redis password injected into app-secrets Secret."
  type        = string
  sensitive   = true
  default     = ""
}

variable "postgres_password" {
  description = "External PostgreSQL password injected into app-secrets Secret."
  type        = string
  sensitive   = true
  default     = ""
}

variable "postgres_user" {
  description = "External PostgreSQL user injected into app-secrets Secret."
  type        = string
  sensitive   = true
  default     = ""
}
