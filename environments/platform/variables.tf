variable "project_name" {
  description = "Project identifier used in tags and naming."
  type        = string
}

variable "environment" {
  description = "Environment name for the platform stack."
  type        = string
}

variable "aws_region" {
  description = "AWS region for the platform stack."
  type        = string
}

variable "infra_state_bucket_name" {
  description = "S3 bucket name that stores the infra Terraform state."
  type        = string
}

variable "infra_state_key" {
  description = "S3 object key for the infra Terraform state."
  type        = string
  default     = "infra/terraform.tfstate"
}

variable "infra_state_region" {
  description = "AWS region of the S3 bucket that stores the infra Terraform state."
  type        = string
}
