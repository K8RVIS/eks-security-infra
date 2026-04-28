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

data "aws_iam_policy_document" "external_secrets_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }

    actions = [
      "sts:AssumeRole",
      "sts:TagSession",
    ]
  }
}

data "aws_iam_policy_document" "external_secrets_access" {
  statement {
    effect = "Allow"

    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]

    resources = var.external_secrets_secret_arns
  }
}

resource "aws_eks_addon" "pod_identity_agent" {
  cluster_name = data.terraform_remote_state.infra.outputs.cluster_name
  addon_name   = "eks-pod-identity-agent"
}

resource "aws_iam_role" "external_secrets" {
  name               = "${data.terraform_remote_state.infra.outputs.cluster_name}-external-secrets"
  assume_role_policy = data.aws_iam_policy_document.external_secrets_assume_role.json
}

resource "aws_iam_role_policy" "external_secrets" {
  name   = "read-workload-runtime-secrets"
  role   = aws_iam_role.external_secrets.id
  policy = data.aws_iam_policy_document.external_secrets_access.json
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
  external_secrets_namespace                 = var.external_secrets_namespace
  external_secrets_chart_version             = var.external_secrets_chart_version
  external_secrets_service_account_name      = var.external_secrets_service_account_name

  depends_on = [
    aws_eks_pod_identity_association.external_secrets,
  ]
}

resource "aws_eks_pod_identity_association" "external_secrets" {
  cluster_name    = data.terraform_remote_state.infra.outputs.cluster_name
  namespace       = var.external_secrets_namespace
  service_account = var.external_secrets_service_account_name
  role_arn        = aws_iam_role.external_secrets.arn

  depends_on = [
    aws_eks_addon.pod_identity_agent,
    aws_iam_role_policy.external_secrets,
  ]
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

  depends_on = [
    module.k8s_base,
    module.namespaces,
    aws_eks_pod_identity_association.external_secrets,
  ]
}
