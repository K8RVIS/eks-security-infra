provider "aws" {
  region                      = "ap-northeast-2"
  access_key                  = "mock-access-key"
  secret_key                  = "mock-secret-key"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_region_validation      = true
  skip_requesting_account_id  = true
}

variables {
  project_name       = "eks-secure-infra"
  environment        = "dev"
  owner              = "K8RVIS"
  cluster_subnet_ids = ["subnet-private-a", "subnet-private-b"]
  node_subnet_ids    = ["subnet-private-a", "subnet-private-b"]
  kubernetes_version = "1.34"
  node_ami_type      = "AL2023_ARM_64_STANDARD"
  cluster_private_endpoint_access_cidrs = [
    "172.31.0.0/16",
  ]

  node_group = {
    instance_types = ["t4g.medium", "t4g.large", "m7g.large", "c7g.large"]
    desired_size   = 3
    min_size       = 2
    max_size       = 4
    disk_size_gb   = 20
  }

  default_tags = {
    Repository = "eks-secure-infra"
    ManagedBy  = "terraform"
  }
}

run "plan_builds_minimal_eks_cluster" {
  command = plan

  assert {
    condition     = aws_eks_cluster.this.name == "eks-secure-infra-dev"
    error_message = "EKS cluster name must follow the project-environment naming convention."
  }

  assert {
    condition     = aws_eks_cluster.this.version == var.kubernetes_version
    error_message = "EKS cluster version must match the configured Kubernetes version."
  }

  assert {
    condition     = length(setsubtract(toset(aws_eks_cluster.this.vpc_config[0].subnet_ids), toset(var.cluster_subnet_ids))) == 0
    error_message = "The EKS control plane must stay on the private cluster subnets."
  }

  assert {
    condition     = aws_eks_cluster.this.vpc_config[0].endpoint_private_access && !aws_eks_cluster.this.vpc_config[0].endpoint_public_access
    error_message = "The EKS cluster API endpoint must be private-only."
  }

  assert {
    condition     = aws_security_group_rule.cluster_private_endpoint_ingress["172.31.0.0/16"].type == "ingress"
    error_message = "The EKS cluster security group must allow VPN VPC ingress to the private API endpoint."
  }

  assert {
    condition     = aws_security_group_rule.cluster_private_endpoint_ingress["172.31.0.0/16"].protocol == "tcp" && aws_security_group_rule.cluster_private_endpoint_ingress["172.31.0.0/16"].from_port == 443 && aws_security_group_rule.cluster_private_endpoint_ingress["172.31.0.0/16"].to_port == 443
    error_message = "Private API endpoint ingress must allow TCP 443."
  }

  assert {
    condition     = contains(aws_security_group_rule.cluster_private_endpoint_ingress["172.31.0.0/16"].cidr_blocks, "172.31.0.0/16")
    error_message = "Private API endpoint ingress must allow the configured VPN VPC CIDR."
  }

  assert {
    condition     = aws_eks_node_group.this.capacity_type == "SPOT"
    error_message = "Managed node group must use SPOT capacity for the cost-optimized lab environment."
  }

  assert {
    condition     = aws_iam_role_policy_attachment.node_ebs_csi_policy.policy_arn == "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
    error_message = "Node role must allow the EBS CSI driver to provision persistent volumes."
  }

  assert {
    condition     = aws_eks_addon.ebs_csi_driver.addon_name == "aws-ebs-csi-driver"
    error_message = "EKS must install the managed EBS CSI driver addon for dynamic EBS volume provisioning."
  }

  assert {
    condition     = aws_eks_addon.vpc_cni.addon_name == "vpc-cni"
    error_message = "EKS must manage the Amazon VPC CNI as an EKS addon."
  }

  assert {
    condition     = aws_eks_addon.vpc_cni.configuration_values == jsonencode({ enableNetworkPolicy = "true" })
    error_message = "The Amazon VPC CNI managed addon must enable NetworkPolicy enforcement."
  }

  assert {
    condition     = length(aws_eks_node_group.this.instance_types) > 1
    error_message = "Managed node group must use multiple spot instance type candidates to reduce interruption concentration risk."
  }

  assert {
    condition     = length(setsubtract(toset(var.node_group.instance_types), toset(aws_eks_node_group.this.instance_types))) == 0
    error_message = "Managed node group must pass through the configured spot instance type candidates."
  }

  assert {
    condition     = !contains(aws_eks_node_group.this.instance_types, "m7g.medium") && !contains(aws_eks_node_group.this.instance_types, "c7g.medium")
    error_message = "Managed node group must avoid small Graviton medium candidates with low pod capacity."
  }

  assert {
    condition     = length(setsubtract(toset(aws_eks_node_group.this.subnet_ids), toset(var.node_subnet_ids))) == 0
    error_message = "The managed node group must use the configured node subnets."
  }

  assert {
    condition     = length([for subnet_id in aws_eks_node_group.this.subnet_ids : subnet_id if can(regex("private", subnet_id))]) == length(aws_eks_node_group.this.subnet_ids)
    error_message = "The managed node group test fixture must exercise private subnet placement."
  }

  assert {
    condition     = aws_eks_node_group.this.ami_type == var.node_ami_type
    error_message = "Managed node group AMI type must match the configured node architecture."
  }

  assert {
    condition     = aws_eks_node_group.this.scaling_config[0].desired_size == var.node_group.desired_size
    error_message = "Managed node group desired size must match the configured value."
  }

  assert {
    condition     = aws_eks_node_group.this.scaling_config[0].desired_size == 3 && aws_eks_node_group.this.scaling_config[0].min_size == 2 && aws_eks_node_group.this.scaling_config[0].max_size == 4
    error_message = "Managed node group must keep enough baseline pod slots for platform addons."
  }

  assert {
    condition     = output.cluster_name == aws_eks_cluster.this.name
    error_message = "The module must expose the EKS cluster name as an output."
  }

  assert {
    condition     = output.node_group_name == aws_eks_node_group.this.node_group_name
    error_message = "The module must expose the managed node group name as an output."
  }

  assert {
    condition     = toset(output.cluster_subnet_ids) == toset(aws_eks_cluster.this.vpc_config[0].subnet_ids)
    error_message = "The module must expose the EKS control plane subnet IDs as an output."
  }

  assert {
    condition     = toset(output.node_subnet_ids) == toset(aws_eks_node_group.this.subnet_ids)
    error_message = "The module must expose the managed node group subnet IDs as an output."
  }
}
