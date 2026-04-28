data "terraform_remote_state" "infra" {
  backend = "s3"

  config = {
    bucket = var.infra_state_bucket_name
    key    = var.infra_state_key
    region = var.infra_state_region
  }
}

data "aws_eks_cluster_auth" "infra" {
  name = data.terraform_remote_state.infra.outputs.cluster_name
}

module "k8s_base" {
  source = "../../modules/k8s-base"

  helm_release_timeout_seconds               = var.helm_release_timeout_seconds
  metrics_server_namespace                   = var.metrics_server_namespace
  metrics_server_chart_version               = var.metrics_server_chart_version
  aws_node_termination_handler_namespace     = var.aws_node_termination_handler_namespace
  aws_node_termination_handler_chart         = var.aws_node_termination_handler_chart
  aws_node_termination_handler_chart_version = var.aws_node_termination_handler_chart_version
  ingress_nginx_namespace                    = var.ingress_nginx_namespace
  ingress_nginx_chart_version                = var.ingress_nginx_chart_version
  external_secrets_namespace     = var.external_secrets_namespace
  external_secrets_chart_version = var.external_secrets_chart_version
  external_secrets_role_arn      = aws_iam_role.external_secrets.arn
}

module "namespaces" {
  source = "../../modules/namespaces"

  project_name = var.project_name
  team_names   = var.team_names

  depends_on = [module.k8s_base]
}

module "argocd" {
  source = "../../modules/argocd"

  helm_release_timeout_seconds  = var.helm_release_timeout_seconds
  argocd_namespace              = var.argocd_namespace
  argocd_chart_version          = var.argocd_chart_version
  argocd_apps_chart_version     = var.argocd_apps_chart_version
  argocd_project_name           = var.argocd_project_name
  gitops_repo_url               = var.gitops_repo_url
  gitops_target_revision        = var.gitops_target_revision
  gitops_applications_base_path = var.gitops_applications_base_path
  team_names                    = var.team_names

  depends_on = [module.k8s_base, module.namespaces]
}

data "aws_caller_identity" "current" {}

locals {
  external_secrets_namespace       = "external-secrets"
  external_secrets_service_account = "external-secrets"
  oidc_provider_url                = replace(data.terraform_remote_state.infra.outputs.cluster_oidc_issuer_url, "https://", "")
  workload_secret_arn              = "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:/training/workload/shared-*"
}

data "aws_iam_policy_document" "external_secrets_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.terraform_remote_state.infra.outputs.cluster_oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_url}:sub"
      values   = ["system:serviceaccount:${local.external_secrets_namespace}:${local.external_secrets_service_account}"]
    }
  }
}

resource "aws_iam_role" "external_secrets" {
  name               = "${var.project_name}-${var.environment}-external-secrets"
  assume_role_policy = data.aws_iam_policy_document.external_secrets_assume_role.json
}

data "aws_iam_policy_document" "external_secrets" {
  statement {
    effect = "Allow"

    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]

    resources = [local.workload_secret_arn]
  }
}

resource "aws_iam_policy" "external_secrets" {
  name   = "${var.project_name}-${var.environment}-external-secrets"
  policy = data.aws_iam_policy_document.external_secrets.json
}

resource "aws_iam_role_policy_attachment" "external_secrets" {
  role       = aws_iam_role.external_secrets.name
  policy_arn = aws_iam_policy.external_secrets.arn
}
