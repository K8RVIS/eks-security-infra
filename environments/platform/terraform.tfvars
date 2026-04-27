project_name = "eks-secure-infra"
environment  = "dev"
aws_region   = "ap-northeast-2"

# Replace with the bootstrap tfstate bucket name before running plan/apply.
infra_state_bucket_name = "eks-secure-infra-tfstate"
infra_state_key         = "infra/terraform.tfstate"
infra_state_region      = "ap-northeast-2"

metrics_server_chart_version = "3.13.0"
ingress_nginx_chart_version  = "4.14.1"
argocd_chart_version         = "9.4.17"
argocd_apps_chart_version    = "2.0.3"
gitops_repo_url              = "https://github.com/K8RVIS/eks-secure-infra.git"

ingress_lb_acm_certificate_arn = "arn:aws:acm:ap-northeast-2:357542025037:certificate/6e95b8cb-8e7a-44ac-a47d-be12cf7a413b"