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
          service.beta.kubernetes.io/aws-load-balancer-type: external
          service.beta.kubernetes.io/aws-load-balancer-nlb-target-type: instance
          service.beta.kubernetes.io/aws-load-balancer-ssl-cert: ${var.ingress_lb_acm_certificate_arn}
          //service.beta.kubernetes.io/aws-load-balancer-ssl-ports: "443"
          service.beta.kubernetes.io/aws-load-balancer-ssl-negotiation-policy: ELBSecurityPolicy-TLS13-1-2-2021-06
    EOT
  ]
}
