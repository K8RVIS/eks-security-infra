project_name = "eks-secure-infra"
environment  = "dev"
aws_region   = "ap-northeast-2"
owner        = "K8RVIS"

vpc_cidr = "10.0.0.0/16"

availability_zones = [
  "ap-northeast-2a",
  "ap-northeast-2c",
]

public_subnet_cidrs = [
  "10.0.1.0/24",
  "10.0.2.0/24",
]

private_subnet_cidrs = [
  "10.0.10.0/24",
  "10.0.20.0/24",
]

cluster_private_endpoint_access_cidrs = [
  "172.31.0.0/16", "10.0.0.0/16"
]

vpn_vpc_id   = "vpc-096c2102f9e82e7e2"
vpn_vpc_cidr = "172.31.0.0/16"

fck_nat_instance_type = "t4g.nano"

default_tags = {
  Repository = "eks-secure-infra"
  ManagedBy  = "terraform"
}

kubernetes_version = "1.34"

node_ami_type = "AL2023_ARM_64_STANDARD"

node_group = {
  instance_types = ["t4g.medium", "t4g.large", "m7g.large", "c7g.large"]
  desired_size   = 3
  min_size       = 2
  max_size       = 4
  disk_size_gb   = 20
}

ecr_repository_names     = ["web", "api", "db"]
ecr_max_image_count      = 10
ecr_untagged_expiry_days = 7

# Inspector triage: suppress findings for package ecosystems that each
# service does not use. Only findings for packages the container actually
# runs will remain ACTIVE and trigger alerts.
triage_suppressions = {
  # nginx 이미지 — PHP·Python·Java·Node.js 생태계 패키지는 실행되지 않음
  web = {
    reason        = "nginx 서비스와 무관한 패키지(PHP·Python·Java·Node.js) 취약점 억제"
    package_names = ["php", "python", "java", "node", "npm", "ruby", "perl", "composer"]
  }
  # Go 바이너리(echo-server) — PHP·Java·Python·Ruby 생태계 패키지는 실행되지 않음
  api = {
    reason        = "Go 기반 echo-server 서비스와 무관한 패키지(PHP·Java·Python·Ruby) 취약점 억제"
    package_names = ["php", "java", "python", "ruby", "perl", "composer", "gradle", "maven"]
  }
  # Redis — 애플리케이션 레이어 패키지(PHP·Java·Node.js·Python)는 실행되지 않음
  db = {
    reason        = "Redis 서비스와 무관한 애플리케이션 레이어 패키지 취약점 억제"
    package_names = ["php", "java", "python", "node", "npm", "ruby", "perl", "composer"]
  }
}
