variable "project_name" {
  type        = string
  description = "Project identifier used in naming and tags."
}

variable "environment" {
  type        = string
  description = "Environment name."
}

variable "owner" {
  type        = string
  description = "Owner tag."
}

variable "bucket_suffix" {
  type        = string
  description = "Suffix for the workload S3 bucket name."
  default     = "workload-access-lab"
}

variable "default_tags" {
  type        = map(string)
  description = "Additional tags."
  default     = {}
}
