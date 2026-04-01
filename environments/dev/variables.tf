variable "project_name" {
  description = "Project identifier used in tags and naming."
  type        = string
}

variable "environment" {
  description = "Environment name for the dev stack."
  type        = string
}

variable "aws_region" {
  description = "AWS region for the dev stack."
  type        = string
}

variable "owner" {
  description = "Owner tag applied to dev resources."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the dev VPC."
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
  description = "Additional tags merged into all dev resources."
  type        = map(string)
  default     = {}
}
