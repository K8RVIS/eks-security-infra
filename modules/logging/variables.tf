variable "project_name" {
  description = "Project identifier used in tags and naming."
  type        = string
}

variable "environment" {
  description = "Environment name used in tags and naming."
  type        = string
}

variable "owner" {
  description = "Owner tag applied to logging resources."
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name. Used to derive CloudWatch log group name and CloudTrail trail name."
  type        = string
}

variable "log_retention_days" {
  description = "Retention period (days) for CloudWatch Log Groups."
  type        = number
  default     = 90

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be a value accepted by AWS CloudWatch (e.g. 7, 14, 30, 60, 90, 180, 365)."
  }
}

variable "cloudtrail_s3_retention_days" {
  description = "Days to retain CloudTrail log files in S3 before expiration."
  type        = number
  default     = 365
}

variable "alert_email" {
  description = "Email address to receive SNS security alert notifications. Leave empty to skip email subscription."
  type        = string
  default     = ""
}

variable "default_tags" {
  description = "Additional tags merged into all logging resources."
  type        = map(string)
  default     = {}
}
