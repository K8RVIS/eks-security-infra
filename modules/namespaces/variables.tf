variable "project_name" {
  description = "Project identifier used in namespace labels."
  type        = string
}

variable "team_names" {
  description = "Team namespace names to create."
  type        = list(string)
  default     = ["team-a", "team-b", "team-c", "team-d"]
}

variable "default_namespace_resource_quota_hard" {
  description = "Default hard resource quota applied to each team namespace."
  type        = map(string)

  default = {
    pods              = "20"
    "requests.cpu"    = "2"
    "requests.memory" = "4Gi"
    "limits.cpu"      = "4"
    "limits.memory"   = "8Gi"
  }
}

variable "namespace_container_default_requests" {
  description = "Default container resource requests applied by LimitRange."
  type        = map(string)

  default = {
    cpu    = "100m"
    memory = "128Mi"
  }
}

variable "namespace_container_default_limits" {
  description = "Default container resource limits applied by LimitRange."
  type        = map(string)

  default = {
    cpu    = "500m"
    memory = "512Mi"
  }
}
