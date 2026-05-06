# 네임스페이스 관리 ClusterRole
resource "kubernetes_cluster_role" "namespace_manager" {
  metadata {
    name = "namespace-manager"
  }

  rule {
    api_groups = [""]
    resources  = ["namespaces"]
    verbs      = ["get", "list", "create", "delete"]
  }
}

# 비리소스(/healthz) 접근 ClusterRole
resource "kubernetes_cluster_role" "health_checker" {
  metadata {
    name = "health-checker"
  }

  rule {
    non_resource_urls = ["/healthz", "/livez"]
    verbs             = ["get"]
  }
}

# 네임스페이스 관리자 Binding
resource "kubernetes_cluster_role_binding" "admin_ns_binding" {
  metadata {
    name = "admin-ns-binding"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.namespace_manager.metadata[0].name
  }
  subject {
    kind      = "ServiceAccount"
    name      = var.admin_sa_name
    namespace = var.admin_sa_namespace
  }
}

# 헬스체크 권한 Binding
resource "kubernetes_cluster_role_binding" "api_health_binding" {
  metadata {
    name = "api-health-binding"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.health_checker.metadata[0].name
  }
  subject {
    kind      = "ServiceAccount"
    name      = var.api_sa_name
    namespace = var.admin_sa_namespace
  }
}