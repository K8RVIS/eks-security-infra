data "terraform_remote_state" "infra" {
  backend = "s3"

  config = {
    bucket = var.infra_state_bucket_name
    key    = var.infra_state_key
    region = var.infra_state_region
  }
}

data "aws_eks_cluster" "infra" {
  name = data.terraform_remote_state.infra.outputs.cluster_name
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

data "http" "aws_load_balancer_controller_iam_policy" {
  url = var.aws_load_balancer_controller_iam_policy_url
}

data "aws_iam_policy_document" "aws_load_balancer_controller_assume_role" {
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

resource "aws_eks_addon" "pod_identity_agent" {
  cluster_name = data.terraform_remote_state.infra.outputs.cluster_name
  addon_name   = "eks-pod-identity-agent"
}

resource "aws_iam_policy" "aws_load_balancer_controller" {
  name   = "${data.terraform_remote_state.infra.outputs.cluster_name}-aws-load-balancer-controller"
  policy = data.http.aws_load_balancer_controller_iam_policy.response_body
}

resource "aws_iam_role" "aws_load_balancer_controller" {
  name               = "${data.terraform_remote_state.infra.outputs.cluster_name}-aws-load-balancer-controller"
  assume_role_policy = data.aws_iam_policy_document.aws_load_balancer_controller_assume_role.json
}

resource "aws_iam_role_policy_attachment" "aws_load_balancer_controller" {
  role       = aws_iam_role.aws_load_balancer_controller.name
  policy_arn = aws_iam_policy.aws_load_balancer_controller.arn
}

resource "kubernetes_service_account" "aws_load_balancer_controller" {
  metadata {
    name      = var.aws_load_balancer_controller_service_account_name
    namespace = var.aws_load_balancer_controller_namespace
  }
}

resource "aws_eks_pod_identity_association" "aws_load_balancer_controller" {
  cluster_name    = data.terraform_remote_state.infra.outputs.cluster_name
  namespace       = var.aws_load_balancer_controller_namespace
  service_account = kubernetes_service_account.aws_load_balancer_controller.metadata[0].name
  role_arn        = aws_iam_role.aws_load_balancer_controller.arn

  depends_on = [
    aws_eks_addon.pod_identity_agent,
    aws_iam_role_policy_attachment.aws_load_balancer_controller,
  ]
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

  aws_region   = var.aws_region
  cluster_name = data.terraform_remote_state.infra.outputs.cluster_name
  vpc_id       = data.terraform_remote_state.infra.outputs.vpc_id

  helm_release_timeout_seconds                      = var.helm_release_timeout_seconds
  metrics_server_namespace                          = var.metrics_server_namespace
  metrics_server_chart_version                      = var.metrics_server_chart_version
  aws_node_termination_handler_namespace            = var.aws_node_termination_handler_namespace
  aws_node_termination_handler_chart                = var.aws_node_termination_handler_chart
  aws_node_termination_handler_chart_version        = var.aws_node_termination_handler_chart_version
  aws_load_balancer_controller_namespace            = var.aws_load_balancer_controller_namespace
  aws_load_balancer_controller_service_account_name = var.aws_load_balancer_controller_service_account_name
  aws_load_balancer_controller_chart_version        = var.aws_load_balancer_controller_chart_version
  ingress_nginx_namespace                           = var.ingress_nginx_namespace
  ingress_nginx_chart_version                       = var.ingress_nginx_chart_version
  external_secrets_namespace                        = var.external_secrets_namespace
  external_secrets_chart_version                    = var.external_secrets_chart_version
  external_secrets_service_account_name             = var.external_secrets_service_account_name
  prometheus_namespace                              = var.prometheus_namespace
  prometheus_chart_version                          = var.prometheus_chart_version
  grafana_admin_password                            = var.grafana_admin_password

  depends_on = [
    aws_eks_pod_identity_association.aws_load_balancer_controller,
    aws_eks_pod_identity_association.external_secrets,
    kubernetes_service_account.aws_load_balancer_controller,
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
