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

locals {
  resource_limited_namespaces = {
    for name, namespace in kubernetes_namespace_v1.teams :
    name => namespace
    if name == "team-a"
  }
}

resource "kubernetes_resource_quota_v1" "teams" {
  for_each = local.resource_limited_namespaces

  metadata {
    name      = "team-resource-quota"
    namespace = each.value.metadata[0].name

    labels = {
      "app.kubernetes.io/part-of" = var.project_name
      "training.k8rvis.io/team"   = each.key
    }
  }

  spec {
    hard = var.default_namespace_resource_quota_hard
  }
}

resource "kubernetes_limit_range_v1" "teams" {
  for_each = local.resource_limited_namespaces

  metadata {
    name      = "team-container-limits"
    namespace = each.value.metadata[0].name

    labels = {
      "app.kubernetes.io/part-of" = var.project_name
      "training.k8rvis.io/team"   = each.key
    }
  }

  spec {
    limit {
      type            = "Container"
      default         = var.namespace_container_default_limits
      default_request = var.namespace_container_default_requests
    }
  }
}
