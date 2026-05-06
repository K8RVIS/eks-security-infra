variable "project_name" {
  description = "Project identifier used in tags and naming."
  type        = string
}

variable "environment" {
  description = "Environment name used in tags and naming."
  type        = string
}

variable "owner" {
  description = "Owner tag applied to VPC peering resources."
  type        = string
}

variable "requester_vpc_id" {
  description = "Requester VPC ID, typically the EKS workload VPC."
  type        = string
}

variable "requester_vpc_cidr" {
  description = "CIDR block for the requester VPC."
  type        = string
}

variable "requester_route_table_ids" {
  description = "Route table IDs in the requester VPC that need routes to the accepter VPC."
  type        = list(string)
}

variable "accepter_vpc_id" {
  description = "Accepter VPC ID, typically the existing VPN VPC."
  type        = string
}

variable "accepter_vpc_cidr" {
  description = "CIDR block for the accepter VPC."
  type        = string
}

variable "accepter_route_table_ids" {
  description = "Route table IDs in the accepter VPC that need routes to the requester VPC."
  type        = list(string)
}

variable "default_tags" {
  description = "Additional tags merged into all VPC peering resources."
  type        = map(string)
  default     = {}
}
