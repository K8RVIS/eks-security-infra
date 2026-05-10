variable "project_name" {
  description = "Project identifier; prepended to every repository name (e.g. 'eks-secure-infra/web')."
  type        = string
}

variable "environment" {
  description = "Environment name used in resource tags."
  type        = string
}

variable "owner" {
  description = "Owner tag applied to ECR resources."
  type        = string
}

variable "repository_names" {
  description = "Short names of the container image repositories to create."
  type        = list(string)
  default     = ["web", "api", "db"]

  validation {
    condition     = length(var.repository_names) > 0
    error_message = "At least one repository name must be provided."
  }
}

variable "max_image_count" {
  description = "Maximum number of images to retain per repository (oldest expire first)."
  type        = number
  default     = 10

  validation {
    condition     = var.max_image_count >= 1
    error_message = "max_image_count must be at least 1."
  }
}

variable "untagged_expiry_days" {
  description = "Days after which untagged images (intermediate build layers) are expired."
  type        = number
  default     = 7

  validation {
    condition     = var.untagged_expiry_days >= 1
    error_message = "untagged_expiry_days must be at least 1."
  }
}

variable "default_tags" {
  description = "Additional tags merged into all ECR resources."
  type        = map(string)
  default     = {}
}