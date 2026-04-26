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
# 네임스페이스 전체 자원 할당량
resource "kubernetes_resource_quota" "team_quota" {
  for_each = toset(var.team_names) # 팀별로 각각 생성

  metadata {
    name      = "${each.key}-quota"
    namespace = kubernetes_namespace_v1.teams[each.key].metadata[0].name
  }

  spec {
    hard = {
      cpu    = "2" #"0.6"
      memory = "4Gi" #"1.2Gi"
      pods   = "10"
    }
  }
}

# 2. 개별 포드 기본 제한값
resource "kubernetes_limit_range" "team_limit_range" {
  for_each = toset(var.team_names)

  metadata {
    name      = "${each.key}-limit-range"
    namespace = kubernetes_namespace_v1.teams[each.key].metadata[0].name
  }

  spec {
    limit {
      type = "Container"
      default = {
        cpu    = "500m"
        memory = "512Mi"
      }
      default_request = {
        cpu    = "250m"
        memory = "256Mi"
      }
    }
  }
}