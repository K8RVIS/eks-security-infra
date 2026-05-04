resource "kubernetes_namespace_v1" "teams" {
  for_each = toset(var.team_names)

  metadata {
    name = each.value
    labels = merge(
      {
        "app.kubernetes.io/part-of" = var.project_name
        "training.k8rvis.io/team"   = each.value
      },
      each.value == "team-b" ? {
        "pod-security.kubernetes.io/enforce"         = "restricted"
        "pod-security.kubernetes.io/enforce-version" = "latest"
      } : {}
    )
  }
}

resource "kubernetes_resource_quota" "teams" {
  for_each = kubernetes_namespace_v1.teams

  metadata {
    name      = "team-quota"
    namespace = each.value.metadata[0].name
  }

  spec {
    hard = {
      "requests.cpu"    = "1"
      "limits.cpu"      = "2"
      "requests.memory" = "1Gi"
      "limits.memory"   = "2Gi"
      "pods"            = "10"
    }
  }
}

resource "kubernetes_limit_range" "teams" {
  for_each = kubernetes_namespace_v1.teams

  metadata {
    name      = "team-limit-range"
    namespace = each.value.metadata[0].name
  }

  spec {
    limit {
      type = "Container"
      default = {
        cpu    = "500m"
        memory = "256Mi"
      }
      default_request = {
        cpu    = "100m"
        memory = "128Mi"
      }
    }
  }
}
