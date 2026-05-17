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
    <<-EOT
    driver:
      kind: modern_ebpf
    falco:
      json_output: true
      json_include_output_property: true
      log_stderr: true
      priority: notice
      stdout_output:
        enabled: true
    customRules:
      k8rvis_rules.yaml: |
        - rule: Shell spawned in container
          desc: A shell was spawned inside a container
          condition: spawned_process and container and proc.name in (bash, sh, dash, zsh, ash, fish)
          output: "Shell spawned in container (user=%user.name container=%container.name image=%container.image.repository:%container.image.tag shell=%proc.name cmdline=%proc.cmdline)"
          priority: WARNING
          tags: [container, shell, k8rvis]
        - rule: Write below etc in container
          desc: A process wrote to the /etc directory inside a container
          condition: open_write and container and fd.name startswith /etc
          output: "Write below /etc in container (user=%user.name container=%container.name image=%container.image.repository:%container.image.tag file=%fd.name)"
          priority: WARNING
          tags: [container, filesystem, k8rvis]
        - rule: Sensitive file read in container
          desc: A process read a sensitive credential file inside a container
          condition: open_read and container and fd.name in (/etc/shadow, /etc/passwd, /etc/sudoers)
          output: "Sensitive file read in container (user=%user.name container=%container.name image=%container.image.repository:%container.image.tag file=%fd.name)"
          priority: CRITICAL
          tags: [container, filesystem, credential_access, k8rvis]
    EOT
  ]
}
