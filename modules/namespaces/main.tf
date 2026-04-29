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

resource "kubernetes_secret_v1" "app_secrets" {
  for_each = toset(var.secret_enabled_teams)

  metadata {
    name      = "app-secrets"
    namespace = each.value
  }

  data = {
    redis-password    = var.redis_password
    redis-url         = "redis://:${var.redis_password}@db:6379/0"
    postgres-password = var.postgres_password
    postgres-user     = var.postgres_user
  }

  depends_on = [kubernetes_namespace_v1.teams]
}
