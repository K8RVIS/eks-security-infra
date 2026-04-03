output "vpc_id" {
  description = "VPC ID for the dev environment."
  value       = module.vpc.vpc_id
}

output "vpc_cidr" {
  description = "CIDR block for the dev VPC."
  value       = module.vpc.vpc_cidr
}

output "public_subnet_ids" {
  description = "Ordered list of public subnet IDs."
  value       = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  description = "Ordered list of private subnet IDs."
  value       = module.vpc.private_subnet_ids
}

output "fck_nat_instance_id" {
  description = "Instance ID of the fck-nat instance."
  value       = module.vpc.fck_nat_instance_id
}

output "fck_nat_ami_id" {
  description = "Automatically selected AMI ID for the fck-nat instance."
  value       = module.vpc.fck_nat_ami_id
}
