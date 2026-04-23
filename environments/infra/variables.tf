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
    instance_types = ["t4g.medium"]
    desired_size   = 2
    min_size       = 1
    max_size       = 3
    disk_size_gb   = 20
  }
}

variable "user_iam_arn" {
  description = "EKS 관리자 권한을 부여할 IAM ARN"
  type        = string
}