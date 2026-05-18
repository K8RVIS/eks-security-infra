terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0"
    }

    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
  }
}

resource "kubernetes_storage_class_v1" "encrypted_gp3" {
  metadata {
    name = "encrypted-gp3"
  }

  storage_provisioner    = "ebs.csi.aws.com"
  reclaim_policy         = "Delete"
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true

  parameters = {
    type      = "gp3"
    encrypted = "true"
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
    enableRebalanceMonitoring: false
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

  depends_on = [helm_release.aws_load_balancer_controller]
}

resource "helm_release" "external_secrets" {
  name             = "external-secrets"
  namespace        = var.external_secrets_namespace
  create_namespace = true
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  version          = var.external_secrets_chart_version
  timeout          = var.helm_release_timeout_seconds
  atomic           = true
  cleanup_on_fail  = true
  wait             = true

  values = [
    yamlencode({
      installCRDs = true
      serviceAccount = {
        create = true
        name   = var.external_secrets_service_account_name
      }
    })
  ]

  depends_on = [helm_release.aws_load_balancer_controller]
}

# ---------------------------------------------------------------------------
# kube-prometheus-stack
#   Prometheus + Grafana + kube-state-metrics + node-exporter 를 한 번에 배포.
#   Grafana sidecar가 grafana_dashboard: "1" 레이블이 붙은 ConfigMap을 자동 감지한다.
# ---------------------------------------------------------------------------
resource "helm_release" "kube_prometheus_stack" {
  name             = "kube-prometheus-stack"
  namespace        = var.prometheus_namespace
  create_namespace = true
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  version          = var.prometheus_chart_version
  timeout          = var.helm_release_timeout_seconds
  atomic           = true
  cleanup_on_fail  = true
  wait             = true

  values = [
    yamlencode({
      prometheus = {
        prometheusSpec = {
          retention = "7d"
          resources = {
            requests = { cpu = "250m", memory = "512Mi" }
            limits   = { cpu = "500m", memory = "1Gi" }
          }
          storageSpec = {
            volumeClaimTemplate = {
              spec = {
                storageClassName = kubernetes_storage_class_v1.encrypted_gp3.metadata[0].name
                accessModes      = ["ReadWriteOnce"]
                resources        = { requests = { storage = "20Gi" } }
              }
            }
          }
        }
      }
      grafana = {
        adminPassword = var.grafana_admin_password
        persistence = {
          enabled          = true
          storageClassName = kubernetes_storage_class_v1.encrypted_gp3.metadata[0].name
          size             = "5Gi"
        }
        sidecar = {
          dashboards = {
            enabled         = true
            label           = "grafana_dashboard"
            searchNamespace = "ALL"
          }
        }
        ingress = {
          enabled          = true
          ingressClassName = "nginx"
          hosts            = ["grafana.${var.cluster_name}.local"]
        }
      }
      alertmanager = {
        enabled = false
      }
    })
  ]

  depends_on = [
    helm_release.ingress_nginx,
    kubernetes_storage_class_v1.encrypted_gp3,
  ]
}
