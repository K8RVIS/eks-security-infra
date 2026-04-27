terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0"
    }
  }
}

resource "helm_release" "metrics_server" {
  name             = "metrics-server"
  namespace        = var.metrics_server_namespace
  create_namespace = true
  repository       = "https://kubernetes-sigs.github.io/metrics-server/"
  chart            = "metrics-server"
  version          = var.metrics_server_chart_version
  timeout          = var.helm_release_timeout_seconds
  atomic           = true
  cleanup_on_fail  = true
  wait             = true

  values = [
    yamlencode({
      args = [
        "--kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname",
        "--kubelet-insecure-tls",
      ]
    })
  ]
}

resource "helm_release" "aws_load_balancer_controller" {
  name             = "aws-load-balancer-controller"
  namespace        = var.aws_load_balancer_controller_namespace
  create_namespace = false
  repository       = "https://aws.github.io/eks-charts"
  chart            = "aws-load-balancer-controller"
  version          = var.aws_load_balancer_controller_chart_version
  timeout          = var.helm_release_timeout_seconds
  atomic           = true
  cleanup_on_fail  = true
  wait             = true

  values = [
    yamlencode({
      clusterName = var.cluster_name
      region      = var.aws_region
      vpcId       = var.vpc_id
      serviceAccount = {
        create = false
        name   = var.aws_load_balancer_controller_service_account_name
      }
    })
  ]
}

resource "helm_release" "external_dns" {
  count = var.external_dns_enabled ? 1 : 0

  name             = "external-dns"
  namespace        = var.external_dns_namespace
  create_namespace = false
  repository       = "https://kubernetes-sigs.github.io/external-dns/"
  chart            = "external-dns"
  version          = var.external_dns_chart_version
  timeout          = var.helm_release_timeout_seconds
  atomic           = true
  cleanup_on_fail  = true
  wait             = true

  values = [
    yamlencode({
      provider = {
        name = "cloudflare"
      }

      sources = ["ingress"]

      domainFilters = var.external_dns_domain_filters

      policy     = var.external_dns_policy
      registry   = "txt"
      txtOwnerId = var.external_dns_txt_owner_id

      env = [
        {
          name = "CF_API_TOKEN"
          valueFrom = {
            secretKeyRef = {
              name = var.external_dns_cloudflare_api_token_secret_name
              key  = "api-token"
            }
          }
        }
      ]

      extraArgs = {
        cloudflare-dns-records-per-page = "5000"
      }
    })
  ]
}

resource "helm_release" "aws_node_termination_handler" {
  name             = "aws-node-termination-handler"
  namespace        = var.aws_node_termination_handler_namespace
  create_namespace = true
  repository       = "oci://public.ecr.aws/aws-ec2/helm"
  chart            = var.aws_node_termination_handler_chart
  version          = var.aws_node_termination_handler_chart_version
  timeout          = var.helm_release_timeout_seconds
  atomic           = true
  cleanup_on_fail  = true
  wait             = true

  values = [
    <<-EOT
    enableSpotInterruptionDraining: true
    enableRebalanceMonitoring: true
    enableScheduledEventDraining: false
    EOT
  ]
}

resource "helm_release" "ingress_nginx" {
  name             = "ingress-nginx"
  namespace        = var.ingress_nginx_namespace
  create_namespace = true
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  version          = var.ingress_nginx_chart_version
  timeout          = var.helm_release_timeout_seconds
  atomic           = true
  cleanup_on_fail  = true
  wait             = true

  values = [
    <<-EOT
    controller:
      ingressClassResource:
        default: true
      service:
        type: LoadBalancer
        annotations:
          service.beta.kubernetes.io/aws-load-balancer-scheme: internet-facing
    EOT
  ]
}
