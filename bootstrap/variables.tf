variable "project_name" {
  description = "Project identifier used in tags and naming."
  type        = string
}

variable "environment" {
  description = "Lifecycle label for the bootstrap stack."
  type        = string
}

variable "aws_region" {
  description = "AWS region for the bootstrap stack."
  type        = string
}

variable "owner" {
  description = "Owner tag applied to bootstrap resources."
  type        = string
}

variable "tfstate_bucket_name" {
  description = "Globally unique S3 bucket name for Terraform state."
  type        = string

  validation {
    condition     = length(trimspace(var.tfstate_bucket_name)) > 0
    error_message = "tfstate_bucket_name must not be empty."
  }
}

variable "default_tags" {
  description = "Additional tags merged into the bootstrap stack."
  type        = map(string)
  default     = {}
}

variable "github_oidc_url" {
  description = "OIDC issuer URL for GitHub Actions."
  type        = string
  default     = "https://token.actions.githubusercontent.com"
}

variable "github_oidc_client_ids" {
  description = "OIDC audiences allowed for the GitHub Actions provider."
  type        = list(string)
  default     = ["sts.amazonaws.com"]
}
