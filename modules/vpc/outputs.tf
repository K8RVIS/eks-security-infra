output "vpc_id" {
  description = "VPC ID for the dev environment."
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "CIDR block for the VPC."
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "Ordered list of public subnet IDs."
  value       = [for az in var.availability_zones : aws_subnet.public[az].id]
}

output "private_subnet_ids" {
  description = "Ordered list of private subnet IDs."
  value       = [for az in var.availability_zones : aws_subnet.private[az].id]
}

output "public_subnet_cidrs" {
  description = "Ordered list of public subnet CIDR blocks."
  value       = [for az in var.availability_zones : aws_subnet.public[az].cidr_block]
}

output "private_subnet_cidrs" {
  description = "Ordered list of private subnet CIDR blocks."
  value       = [for az in var.availability_zones : aws_subnet.private[az].cidr_block]
}

output "public_route_table_id" {
  description = "Public route table ID."
  value       = aws_route_table.public.id
}

output "private_route_table_id" {
  description = "Private route table ID."
  value       = aws_route_table.private.id
}

output "fck_nat_instance_id" {
  description = "Instance ID of the fck-nat instance."
  value       = aws_instance.fck_nat.id
}

output "fck_nat_ami_id" {
  description = "Automatically selected AMI ID for the fck-nat instance."
  value       = data.aws_ami.fck_nat.id
}
