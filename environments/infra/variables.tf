variable "project_name" {
  description = "Project identifier used in tags and naming."
  type        = string
}

variable "environment" {
  description = "Environment name for the infra stack."
  type        = string
}

variable "aws_region" {
  description = "AWS region for the infra stack."
  type        = string
}

variable "owner" {
  description = "Owner tag applied to infra resources."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the infra VPC."
  type        = string
}

variable "availability_zones" {
  description = "Availability zones used for the two-AZ VPC layout."
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets ordered by availability zone."
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets ordered by availability zone."
  type        = list(string)
}

variable "cluster_private_endpoint_access_cidrs" {
  description = "Private CIDR blocks allowed to access the infra EKS private API endpoint."
  type        = list(string)
  default     = []
}

variable "vpn_vpc_id" {
  description = "Existing VPN VPC ID peered with the infra VPC for private EKS API access."
  type        = string
}

variable "vpn_vpc_cidr" {
  description = "CIDR block for the existing VPN VPC."
  type        = string
}

variable "fck_nat_instance_type" {
  description = "Instance type for the fck-nat instance."
  type        = string
  default     = "t4g.nano"
}

variable "default_tags" {
  description = "Additional tags merged into all infra resources."
  type        = map(string)
  default     = {}
}

variable "kubernetes_version" {
  description = "Kubernetes version for the infra EKS cluster."
  type        = string
  default     = "1.34"
}

variable "node_ami_type" {
  description = "AMI type for the default infra EKS managed node group."
  type        = string
  default     = "AL2023_ARM_64_STANDARD"
}

variable "node_group" {
  description = "Configuration for the default EKS managed node group."
  type = object({
    instance_types = list(string)
    desired_size   = number
    min_size       = number
    max_size       = number
    disk_size_gb   = number
  })

  default = {
    instance_types = ["t4g.medium", "t4g.large", "m7g.large", "c7g.large"]
    desired_size   = 3
    min_size       = 2
    max_size       = 4
    disk_size_gb   = 20
  }

}
variable "user_iam_arn" {
  description = "EKS 관리자 권한을 부여할 IAM ARN"
  type        = map(string)
  default     = {}
}


variable "ecr_repository_names" {
  description = "Short names of the ECR repositories to create (prefixed with project_name)."
  type        = list(string)
  default     = ["web", "api", "db"]
}

variable "ecr_max_image_count" {
  description = "Maximum number of images to retain per ECR repository."
  type        = number
  default     = 10
}

variable "ecr_untagged_expiry_days" {
  description = "Days after which untagged ECR images are expired."
  type        = number
  default     = 7
}

variable "enabled_cluster_log_types" {
  description = "CloudWatch Logs로 전송할 EKS control plane 로그 타입."
  type        = list(string)
  default     = ["api", "audit", "authenticator"]
}

variable "break_glass_enabled" {
  description = "Break-glass Role, EKS 관리자 access entry, 탐지 알림 리소스를 생성할지 여부."
  type        = bool
  default     = false
}

variable "break_glass_trusted_principal_arns" {
  description = "Break-glass Role을 AssumeRole 할 수 있는 IAM Principal ARN 목록."
  type        = list(string)
  default     = []
}

variable "break_glass_alert_email_addresses" {
  description = "Break-glass 및 고위험 Kubernetes API 탐지 알림을 받을 이메일 주소 목록."
  type        = list(string)
  default     = []
}

variable "break_glass_alarm_evaluation_period_minutes" {
  description = "Break-glass 및 고위험 Kubernetes API 알람 평가 주기(분)."
  type        = number
  default     = 5
}

variable "eks_control_plane_log_retention_days" {
  description = "EKS control plane CloudWatch 로그 보관 기간(일)."
  type        = number
  default     = 30
}

variable "break_glass_require_mfa" {
  description = "IAM AssumeRole 요청에 MFA 조건을 강제할지 여부."
  type        = bool
  default     = false
}

variable "break_glass_jit_grant_ttl_minutes" {
  description = "GitHub Actions JIT 권한 부여 기본 유지 시간(분)."
  type        = number
  default     = 60
}

variable "break_glass_jit_state_retention_days" {
  description = "Break-glass JIT 상태 레코드 보관 기간(일)."
  type        = number
  default     = 30
}
