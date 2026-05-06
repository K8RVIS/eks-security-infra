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

resource "kubernetes_network_policy_v1" "default_deny_ingress" {
  for_each = toset(var.team_names)

  metadata {
    name      = "default-deny-ingress"
    namespace = each.value
  }

  spec {
    pod_selector {}
    policy_types = ["Ingress"]
  }

  depends_on = [kubernetes_namespace_v1.teams]
}

resource "kubernetes_network_policy_v1" "default_deny_egress" {
  for_each = toset(var.team_names)

  metadata {
    name      = "default-deny-egress"
    namespace = each.value
  }

  spec {
    pod_selector {}
    policy_types = ["Egress"]
  }

  depends_on = [kubernetes_namespace_v1.teams]
}
