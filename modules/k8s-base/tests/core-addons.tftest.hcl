mock_provider "helm" {
  override_during = plan
}

mock_provider "kubernetes" {
  override_during = plan
}

variables {
  metrics_server_chart_version       = "3.13.0"
  ingress_nginx_chart_version        = "4.14.1"
  aws_node_termination_handler_chart = "aws-node-termination-handler"
  aws_region                         = "ap-northeast-2"
  cluster_name                       = "eks-secure-infra-dev"
  vpc_id                             = "vpc-0123456789abcdef0"
}

run "plan_deploys_core_addons" {
  command = plan

  assert {
    condition     = helm_release.metrics_server.name == "metrics-server"
    error_message = "Metrics Server release must use the expected release name."
  }

  assert {
    condition     = helm_release.metrics_server.repository == "https://kubernetes-sigs.github.io/metrics-server/"
    error_message = "Metrics Server must use the official helm repository."
  }

  assert {
    condition     = helm_release.metrics_server.version == var.metrics_server_chart_version
    error_message = "Metrics Server must pin the configured chart version."
  }

  assert {
    condition     = helm_release.aws_node_termination_handler.name == "aws-node-termination-handler"
    error_message = "Node Termination Handler release must use the expected release name."
  }

  assert {
    condition     = helm_release.aws_node_termination_handler.chart == var.aws_node_termination_handler_chart
    error_message = "Node Termination Handler must use the expected chart name."
  }

  assert {
    condition     = strcontains(join("", helm_release.aws_node_termination_handler.values), "enableSpotInterruptionDraining: true")
    error_message = "Node Termination Handler must enable spot interruption draining."
  }

  assert {
    condition     = strcontains(join("", helm_release.aws_node_termination_handler.values), "enableRebalanceMonitoring: false")
    error_message = "Node Termination Handler must not cordon spot nodes on rebalance recommendations in the cost-optimized lab cluster."
  }

  assert {
    condition     = helm_release.ingress_nginx.name == "ingress-nginx"
    error_message = "Ingress NGINX release must use the expected release name."
  }

  assert {
    condition     = helm_release.ingress_nginx.version == var.ingress_nginx_chart_version
    error_message = "Ingress NGINX must pin the configured chart version."
  }

  assert {
    condition     = strcontains(join("", helm_release.ingress_nginx.values), "aws-load-balancer-scheme: internet-facing")
    error_message = "Ingress NGINX service must expose a public load balancer."
  }

  assert {
    condition     = output.ingress_service_name == "ingress-nginx-controller"
    error_message = "The module must expose the ingress controller service name."
  }

  assert {
    condition     = kubernetes_storage_class_v1.encrypted_gp3.metadata[0].name == "encrypted-gp3"
    error_message = "The platform module must create the encrypted-gp3 StorageClass."
  }

  assert {
    condition     = kubernetes_storage_class_v1.encrypted_gp3.storage_provisioner == "ebs.csi.aws.com"
    error_message = "The encrypted StorageClass must use the AWS EBS CSI Driver."
  }

  assert {
    condition     = kubernetes_storage_class_v1.encrypted_gp3.parameters.type == "gp3"
    error_message = "The encrypted StorageClass must provision gp3 volumes."
  }

  assert {
    condition     = kubernetes_storage_class_v1.encrypted_gp3.parameters.encrypted == "true"
    error_message = "The encrypted StorageClass must explicitly enable EBS encryption."
  }

  assert {
    condition     = output.encrypted_storage_class_name == "encrypted-gp3"
    error_message = "The module must expose the encrypted StorageClass name."
  }

  assert {
    condition     = helm_release.external_secrets.name == "external-secrets"
    error_message = "External Secrets Operator release must use the expected release name."
  }

  assert {
    condition     = helm_release.external_secrets.repository == "https://charts.external-secrets.io"
    error_message = "External Secrets Operator must use the official helm repository."
  }

  assert {
    condition     = helm_release.external_secrets.chart == "external-secrets"
    error_message = "External Secrets Operator must install the external-secrets chart."
  }

  assert {
    condition     = helm_release.external_secrets.namespace == var.external_secrets_namespace
    error_message = "External Secrets Operator must deploy into the configured namespace."
  }
}
