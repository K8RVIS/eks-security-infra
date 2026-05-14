project_name = "eks-secure-infra"
environment  = "dev"
aws_region   = "ap-northeast-2"

# Replace with the bootstrap tfstate bucket name before running plan/apply.
infra_state_bucket_name = "eks-secure-infra-tfstate"
infra_state_key         = "infra/terraform.tfstate"
infra_state_region      = "ap-northeast-2"


cloudflare_zone_id = "ae86e28ffa7d6b1f86584d8d106d7043"
acm_dns_validation_records = {
  terraform_study_esc_shop = {
    name    = "_f9cf93ba3be5471b7d1ef382ff592f1e"
    content = "_b4982505b75b312208f9a581ff4421f2.jkddzztszm.acm-validations.aws"
  }
}

metrics_server_chart_version               = "3.13.0"
ingress_nginx_chart_version                = "4.14.1"
aws_load_balancer_controller_chart_version = "3.2.2"
argocd_chart_version                       = "9.4.17"
argocd_apps_chart_version                  = "2.0.3"
gitops_repo_url                            = "https://github.com/K8RVIS/eks-secure-infra.git"
