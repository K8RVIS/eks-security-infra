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
}
