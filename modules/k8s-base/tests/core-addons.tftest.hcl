mock_provider "helm" {
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
    condition     = helm_release.aws_load_balancer_controller.name == "aws-load-balancer-controller"
    error_message = "AWS Load Balancer Controller release must use the expected release name."
  }

  assert {
    condition     = helm_release.aws_load_balancer_controller.repository == "https://aws.github.io/eks-charts"
    error_message = "AWS Load Balancer Controller must use the official EKS charts repository."
  }

  assert {
    condition     = helm_release.aws_load_balancer_controller.version == var.aws_load_balancer_controller_chart_version
    error_message = "AWS Load Balancer Controller must pin the configured chart version."
  }

  assert {
    condition     = strcontains(join("", helm_release.aws_load_balancer_controller.values), "serviceAccount")
    error_message = "AWS Load Balancer Controller values must configure the pre-created IRSA service account."
  }

  assert {
    condition     = output.aws_load_balancer_controller_release_name == "aws-load-balancer-controller"
    error_message = "The module must expose the AWS Load Balancer Controller release name."
  }
}
