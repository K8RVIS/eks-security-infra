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
