mock_provider "aws" {
  override_during = plan
}

variables {
  project_name          = "eks-secure-infra"
  environment           = "dev"
  aws_region            = "ap-northeast-2"
  owner                 = "K8RVIS"
  vpc_cidr              = "10.0.0.0/16"
  availability_zones    = ["ap-northeast-2a", "ap-northeast-2c"]
  public_subnet_cidrs   = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnet_cidrs  = ["10.0.10.0/24", "10.0.20.0/24"]
  fck_nat_instance_type = "t4g.nano"
  default_tags = {
    Repository = "eks-secure-infra"
    ManagedBy  = "terraform"
  }
}

run "creates_expected_network_layout" {
  command = apply

  assert {
    condition     = aws_vpc.this.cidr_block == "10.0.0.0/16"
    error_message = "VPC CIDR must match the documented 10.0.0.0/16 range."
  }

  assert {
    condition     = length(aws_subnet.public) == 2
    error_message = "Two public subnets must be created for the two-AZ layout."
  }

  assert {
    condition     = length(aws_subnet.private) == 2
    error_message = "Two private subnets must be created for worker nodes."
  }

  assert {
    condition     = aws_subnet.public["ap-northeast-2a"].cidr_block == "10.0.1.0/24"
    error_message = "Public subnet A must use 10.0.1.0/24."
  }

  assert {
    condition     = aws_subnet.private["ap-northeast-2c"].cidr_block == "10.0.20.0/24"
    error_message = "Private subnet B must use 10.0.20.0/24."
  }

  assert {
    condition     = aws_instance.fck_nat.subnet_id == aws_subnet.public["ap-northeast-2a"].id
    error_message = "fck-nat must be placed in Public Subnet A."
  }

  assert {
    condition     = aws_instance.fck_nat.instance_type == "t4g.nano"
    error_message = "fck-nat must default to the documented t4g.nano instance type."
  }

  assert {
    condition     = aws_instance.fck_nat.ami == data.aws_ami.fck_nat.id
    error_message = "fck-nat must use the automatically discovered official AMI."
  }

  assert {
    condition     = aws_instance.fck_nat.source_dest_check == false
    error_message = "fck-nat must disable source/destination checks."
  }

  assert {
    condition     = aws_route.private_default.network_interface_id == aws_instance.fck_nat.primary_network_interface_id
    error_message = "Private subnet default route must point to the fck-nat primary network interface."
  }
}
