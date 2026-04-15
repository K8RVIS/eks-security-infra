mock_provider "helm" {
  override_during = plan
}

variables {
  argocd_chart_version           = "9.4.17"
  argocd_apps_chart_version      = "2.0.3"
  gitops_repo_url                = "https://github.com/K8RVIS/eks-secure-infra.git"
  gitops_target_revision         = "main"
  gitops_applications_base_path = "manifests/overlays"
  team_names                     = ["team-a", "team-b", "team-c", "team-d"]
}

run "plan_deploys_argocd_and_team_applications" {
  command = plan

  assert {
    condition     = helm_release.argocd.name == "argocd"
    error_message = "ArgoCD release must use the expected release name."
  }

  assert {
    condition     = helm_release.argocd.repository == "https://argoproj.github.io/argo-helm"
    error_message = "ArgoCD must use the official helm repository."
  }

  assert {
    condition     = helm_release.argocd.chart == "argo-cd"
    error_message = "ArgoCD must use the official chart name."
  }

  assert {
    condition     = helm_release.argocd.version == var.argocd_chart_version
    error_message = "ArgoCD must pin the configured chart version."
  }

  assert {
    condition     = helm_release.argocd_apps.chart == "argocd-apps"
    error_message = "Team applications must be installed via the argocd-apps chart."
  }

  assert {
    condition     = helm_release.argocd_apps.version == var.argocd_apps_chart_version
    error_message = "argocd-apps must pin the configured chart version."
  }

  assert {
    condition     = strcontains(join("", helm_release.argocd_apps.values), "\"repoURL\": \"https://github.com/K8RVIS/eks-secure-infra.git\"")
    error_message = "ArgoCD applications must target the configured GitOps repository."
  }

  assert {
    condition     = strcontains(join("", helm_release.argocd_apps.values), "\"path\": \"manifests/overlays/team-a\"")
    error_message = "Team applications must point at the team overlay path."
  }

  assert {
    condition     = strcontains(join("", helm_release.argocd_apps.values), "CreateNamespace=true")
    error_message = "Team applications must request namespace creation during sync."
  }

  assert {
    condition     = output.argocd_server_service_name == "argocd-server"
    error_message = "The module must expose the ArgoCD server service name."
  }
}
