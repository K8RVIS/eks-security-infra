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

variable "cluster_public_access_cidrs" {
  description = "CIDR blocks allowed to access the infra EKS public API endpoint."
  type        = list(string)
  default     = []
}

variable "cluster_endpoint_private_access" {
  description = "Whether the infra EKS private API endpoint is enabled."
  type        = bool
  default     = true
}

variable "cluster_endpoint_public_access" {
  description = "Whether the infra EKS public API endpoint is enabled."
  type        = bool
  default     = false
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

variable "enable_vpn_private_api_access" {
  description = "Whether to connect the VPN/self-hosted runner VPC to the EKS private API endpoint."
  type        = bool
  default     = false
}

variable "vpn_vpc_id" {
  description = "VPC ID where the VPN/self-hosted runner is running."
  type        = string
  default     = null
}

variable "vpn_vpc_cidr" {
  description = "CIDR block of the VPN/self-hosted runner VPC."
  type        = string
  default     = null
}

variable "vpn_route_table_ids" {
  description = "Route table IDs used by the VPN/self-hosted runner subnets."
  type        = list(string)
  default     = []
}
