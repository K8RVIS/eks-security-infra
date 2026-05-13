locals {
  team_applications = {
    for team_name in var.team_names : team_name => {
      namespace = var.argocd_namespace
      project   = var.argocd_project_name
      source = {
        repoURL        = var.gitops_repo_url
        targetRevision = var.gitops_target_revision
        path           = "${var.gitops_applications_base_path}/${team_name}"
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = team_name
      }
      syncPolicy = {
        automated = {
          prune    = true
          selfHeal = true
        }
        syncOptions = ["CreateNamespace=true"]
      }
    }
  }
}

resource "helm_release" "argocd" {
  name             = "argocd"
  namespace        = var.argocd_namespace
  create_namespace = true
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.argocd_chart_version
  timeout          = var.helm_release_timeout_seconds
  atomic           = true
  cleanup_on_fail  = true
  wait             = true

  values = [
    yamlencode({
      crds = {
        install = true
      }
      configs = {
        params = {
          "server.insecure" = true
        }
      }
    })
  ]
}

resource "helm_release" "argocd_apps" {
  name            = "argocd-apps"
  namespace       = var.argocd_namespace
  repository      = "https://argoproj.github.io/argo-helm"
  chart           = "argocd-apps"
  version         = var.argocd_apps_chart_version
  timeout         = var.helm_release_timeout_seconds
  atomic          = true
  cleanup_on_fail = true
  wait            = true

  values = [
    yamlencode({
      applications = local.team_applications
    })
  ]

  depends_on = [helm_release.argocd]
}
