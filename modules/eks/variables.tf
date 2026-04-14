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
    instance_types = ["t4g.medium"]
    desired_size   = 2
    min_size       = 1
    max_size       = 3
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
