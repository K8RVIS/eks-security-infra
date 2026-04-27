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

data "aws_iam_openid_connect_provider" "infra" {
  url = data.aws_eks_cluster.infra.identity[0].oidc[0].issuer
}

data "http" "aws_load_balancer_controller_iam_policy" {
  url = var.aws_load_balancer_controller_iam_policy_url
}

locals {
  eks_oidc_provider = replace(data.aws_eks_cluster.infra.identity[0].oidc[0].issuer, "https://", "")
}

data "aws_iam_policy_document" "aws_load_balancer_controller_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.infra.arn]
    }

    actions = ["sts:AssumeRoleWithWebIdentity"]

    condition {
      test     = "StringEquals"
      variable = "${local.eks_oidc_provider}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.eks_oidc_provider}:sub"
      values   = ["system:serviceaccount:${var.aws_load_balancer_controller_namespace}:${var.aws_load_balancer_controller_service_account_name}"]
    }
  }
}

resource "aws_iam_policy" "aws_load_balancer_controller" {
  name   = "AWSLoadBalancerControllerIAMPolicy"
  policy = data.http.aws_load_balancer_controller_iam_policy.response_body
}

resource "aws_iam_role" "aws_load_balancer_controller" {
  name               = "AmazonEKSLoadBalancerControllerRole"
  assume_role_policy = data.aws_iam_policy_document.aws_load_balancer_controller_assume_role.json

  lifecycle {
    ignore_changes = [
      tags,
    ]
  }
}

resource "aws_iam_role_policy_attachment" "aws_load_balancer_controller" {
  role       = aws_iam_role.aws_load_balancer_controller.name
  policy_arn = aws_iam_policy.aws_load_balancer_controller.arn
}

resource "kubernetes_service_account_v1" "aws_load_balancer_controller" {
  automount_service_account_token = false

  metadata {
    name      = var.aws_load_balancer_controller_service_account_name
    namespace = var.aws_load_balancer_controller_namespace

    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.aws_load_balancer_controller.arn
    }
  }

  lifecycle {
    ignore_changes = [
      metadata[0].labels,
    ]
  }
}

resource "kubernetes_secret_v1" "external_dns_cloudflare" {
  count = var.cloudflare_api_token == null ? 0 : 1

  metadata {
    name      = var.external_dns_cloudflare_api_token_secret_name
    namespace = var.external_dns_namespace
  }

  data = {
    api-token = var.cloudflare_api_token
  }

  type = "Opaque"
}

module "k8s_base" {
  source = "../../modules/k8s-base"

  aws_region                                        = var.aws_region
  cluster_name                                      = data.terraform_remote_state.infra.outputs.cluster_name
  vpc_id                                            = data.terraform_remote_state.infra.outputs.vpc_id
  helm_release_timeout_seconds                      = var.helm_release_timeout_seconds
  metrics_server_namespace                          = var.metrics_server_namespace
  metrics_server_chart_version                      = var.metrics_server_chart_version
  aws_node_termination_handler_namespace            = var.aws_node_termination_handler_namespace
  aws_node_termination_handler_chart                = var.aws_node_termination_handler_chart
  aws_node_termination_handler_chart_version        = var.aws_node_termination_handler_chart_version
  aws_load_balancer_controller_namespace            = var.aws_load_balancer_controller_namespace
  aws_load_balancer_controller_service_account_name = var.aws_load_balancer_controller_service_account_name
  aws_load_balancer_controller_chart_version        = var.aws_load_balancer_controller_chart_version
  external_dns_enabled                              = var.cloudflare_api_token != null
  external_dns_namespace                            = var.external_dns_namespace
  external_dns_chart_version                        = var.external_dns_chart_version
  external_dns_domain_filters                       = var.external_dns_domain_filters
  external_dns_txt_owner_id                         = var.external_dns_txt_owner_id
  external_dns_policy                               = var.external_dns_policy
  external_dns_cloudflare_api_token_secret_name     = var.external_dns_cloudflare_api_token_secret_name
  ingress_nginx_namespace                           = var.ingress_nginx_namespace
  ingress_nginx_chart_version                       = var.ingress_nginx_chart_version

  depends_on = [
    aws_iam_role_policy_attachment.aws_load_balancer_controller,
    kubernetes_service_account_v1.aws_load_balancer_controller,
    kubernetes_secret_v1.external_dns_cloudflare,
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

  depends_on = [module.k8s_base, module.namespaces]
}
