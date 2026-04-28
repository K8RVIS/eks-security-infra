resource "kubernetes_namespace_v1" "teams" {
  for_each = toset(var.team_names)

  metadata {
    name = each.value
    labels = {
      "app.kubernetes.io/part-of" = var.project_name
      "training.k8rvis.io/team"   = each.value
    }
  }
}

variable "default_namespace_resource_quota_hard" {
  description = "Default hard resource quota applied to the limited namespace."
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