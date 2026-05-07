resource "kubernetes_namespace_v1" "teams" {
  for_each = toset(var.team_names)

  metadata {
    name = each.value
    labels = {
      "app.kubernetes.io/part-of"                  = var.project_name
      "training.k8rvis.io/team"                    = each.value
      "pod-security.kubernetes.io/enforce"         = "baseline"
      "pod-security.kubernetes.io/enforce-version" = "latest"
      "pod-security.kubernetes.io/audit"           = "baseline"
      "pod-security.kubernetes.io/audit-version"   = "latest"
      "pod-security.kubernetes.io/warn"            = "baseline"
      "pod-security.kubernetes.io/warn-version"    = "latest"
    }
  }
}

resource "kubernetes_resource_quota" "teams" {
  for_each = toset(var.team_names)

  metadata {
    name      = "team-quota"
    namespace = each.value
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
  for_each = toset(var.team_names)

  metadata {
    name      = "team-limit-range"
    namespace = each.value
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
