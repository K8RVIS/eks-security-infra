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

output "fck_nat_subnet_id" {
  description = "Subnet ID where the fck-nat instance is placed."
  value       = aws_instance.fck_nat.subnet_id
}

output "fck_nat_primary_network_interface_id" {
  description = "Primary network interface ID of the fck-nat instance."
  value       = aws_instance.fck_nat.primary_network_interface_id
}

output "fck_nat_ami_id" {
  description = "Automatically selected AMI ID for the fck-nat instance."
  value       = data.aws_ami.fck_nat.id
}

output "private_default_route_network_interface_id" {
  description = "Network interface ID targeted by the private default route."
  value       = aws_route.private_default.network_interface_id
}
