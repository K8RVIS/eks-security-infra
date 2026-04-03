mock_provider "kubernetes" {
  override_during = plan
}

variables {
  project_name = "eks-security-infra"
  team_names   = ["team-a", "team-b", "team-c", "team-d"]
}

run "plan_creates_empty_team_namespaces" {
  command = plan

  assert {
    condition     = kubernetes_namespace_v1.teams["team-a"].metadata[0].name == "team-a"
    error_message = "team-a namespace must be created."
  }

  assert {
    condition     = kubernetes_namespace_v1.teams["team-d"].metadata[0].name == "team-d"
    error_message = "team-d namespace must be created."
  }

  assert {
    condition     = kubernetes_namespace_v1.teams["team-b"].metadata[0].labels["training.k8rvis.io/team"] == "team-b"
    error_message = "Each namespace must carry its team label."
  }

  assert {
    condition     = length(output.namespace_names) == 4
    error_message = "The module must expose all team namespace names."
  }
}
