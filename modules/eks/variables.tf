variable "project_name" {
  description = "Project identifier used in tags and naming."
  type        = string
}

variable "environment" {
  description = "Environment name used in tags and naming."
  type        = string
}

variable "owner" {
  description = "Owner tag applied to EKS resources."
  type        = string
}

variable "cluster_subnet_ids" {
  description = "Subnet IDs used by the EKS control plane."
  type        = list(string)

  validation {
    condition     = length(var.cluster_subnet_ids) >= 2
    error_message = "At least two subnets must be supplied for the EKS control plane."
  }
}

variable "node_subnet_ids" {
  description = "Subnet IDs used by the default managed node group."
  type        = list(string)

  validation {
    condition     = length(var.node_subnet_ids) >= 2
    error_message = "At least two subnets must be supplied for the managed node group."
  }
}

variable "cluster_private_endpoint_access_cidrs" {
  description = "Private CIDR blocks allowed to access the EKS private API endpoint through the cluster security group."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for cidr in var.cluster_private_endpoint_access_cidrs : can(cidrhost(cidr, 0))])
    error_message = "Each private endpoint access CIDR must be a valid CIDR block."
  }

  validation {
    condition     = !contains(var.cluster_private_endpoint_access_cidrs, "0.0.0.0/0") && !contains(var.cluster_private_endpoint_access_cidrs, "::/0")
    error_message = "Do not allow 0.0.0.0/0 or ::/0 to the EKS private API endpoint."
  }
}

variable "kubernetes_version" {
  description = "Kubernetes version for the EKS cluster and managed node group."
  type        = string
  default     = "1.34"
}

variable "node_ami_type" {
  description = "AMI type for the default managed node group."
  type        = string
  default     = "AL2023_ARM_64_STANDARD"
}

variable "node_group" {
  description = "Configuration for the default managed node group."
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

  validation {
    condition     = length(var.node_group.instance_types) > 0
    error_message = "At least one instance type must be supplied for the managed node group."
  }

  validation {
    condition     = var.node_group.min_size <= var.node_group.desired_size && var.node_group.desired_size <= var.node_group.max_size
    error_message = "Managed node group scaling values must satisfy min_size <= desired_size <= max_size."
  }
}

variable "default_tags" {
  description = "Additional tags merged into all EKS resources."
  type        = map(string)
  default     = {}
}
variable "access_entries" {
  description = "EKS cluster에 접속할 IAM user 및 권한 mapping"
  type        = any
  default     = {}
}

variable "authentication_mode" {
  description = "EKS 클러스터 인증 모드"
  type        = string
  default     = "API_AND_CONFIG_MAP"
}

variable "cluster_enabled_log_types" {
  description = "EKS control plane log types enabled for audit visibility."
  type        = list(string)
  default     = ["audit", "authenticator"]

  validation {
    condition = alltrue([
      for log_type in var.cluster_enabled_log_types :
      contains(["api", "audit", "authenticator", "controllerManager", "scheduler"], log_type)
    ])
    error_message = "Valid EKS control plane log types are api, audit, authenticator, controllerManager, scheduler."
  }
}

variable "control_plane_log_retention_days" {
  description = "CloudWatch retention days for the EKS control plane log group."
  type        = number
  default     = 7
}
