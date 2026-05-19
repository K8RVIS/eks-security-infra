terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0"
    }
  }
}

locals {
  falco_values       = yamldecode(file("${path.module}/values/falco-values.yaml"))
  falco_custom_rules = file("${path.module}/rules/falco-custom-rules.yaml")
}

resource "helm_release" "falco" {
  name             = "falco"
  namespace        = var.falco_namespace
  create_namespace = true
  repository       = "https://falcosecurity.github.io/charts"
  chart            = "falco"
  version          = var.falco_chart_version
  timeout          = var.helm_release_timeout_seconds
  atomic           = true
  cleanup_on_fail  = true
  wait             = true

  values = [
    yamlencode(merge(local.falco_values, {
      customRules = {
        "falco-custom-rules.yaml" = local.falco_custom_rules
      }
    }))
  ]
}
