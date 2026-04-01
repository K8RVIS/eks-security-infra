data "aws_ami" "fck_nat" {
  most_recent = true
  owners      = ["568608671756"]

  filter {
    name   = "name"
    values = ["fck-nat-al2023-*-arm64-ebs"]
  }

  filter {
    name   = "architecture"
    values = ["arm64"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_security_group" "fck_nat" {
  name        = "${var.project_name}-${var.environment}-fck-nat"
  description = "Security group for the fck-nat instance"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "Allow private subnet traffic to be NATed"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "Allow outbound internet traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${var.project_name}-${var.environment}-fck-nat-sg"
    }
  )
}

resource "aws_instance" "fck_nat" {
  ami                         = data.aws_ami.fck_nat.id
  instance_type               = var.fck_nat_instance_type
  subnet_id                   = aws_subnet.public[local.nat_az].id
  associate_public_ip_address = true
  source_dest_check           = false
  vpc_security_group_ids      = [aws_security_group.fck_nat.id]

  instance_market_options {
    market_type = "spot"

    spot_options {
      instance_interruption_behavior = "terminate"
      spot_instance_type             = "one-time"
    }
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${var.project_name}-${var.environment}-fck-nat"
      Role = "fck-nat"
    }
  )
}
