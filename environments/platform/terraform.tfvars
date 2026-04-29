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

ingress_lb_acm_certificate_arn = null

cloudflare_zone_id = "ae86e28ffa7d6b1f86584d8d106d7043"

ingress_certificate_domain_name               = "*.terraform-study-esc.shop"
ingress_certificate_subject_alternative_names = []
