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
  project_name       = "eks-security-infra"
  environment        = "dev"
  owner              = "K8RVIS"
  private_subnet_ids = ["subnet-11111111", "subnet-22222222"]
  kubernetes_version = "1.34"
  node_ami_type      = "AL2023_ARM_64_STANDARD"

  node_group = {
    instance_types = ["t4g.medium"]
    desired_size   = 2
    min_size       = 1
    max_size       = 3
    disk_size_gb   = 20
  }

  default_tags = {
    Repository = "eks-security-infra"
    ManagedBy  = "terraform"
  }
}

run "plan_builds_minimal_eks_cluster" {
  command = plan

  assert {
    condition     = aws_eks_cluster.this.name == "eks-security-infra-dev"
    error_message = "EKS cluster name must follow the project-environment naming convention."
  }

  assert {
    condition     = aws_eks_cluster.this.version == var.kubernetes_version
    error_message = "EKS cluster version must match the configured Kubernetes version."
  }

  assert {
    condition     = aws_eks_node_group.this.capacity_type == "SPOT"
    error_message = "Managed node group must use SPOT capacity for the cost-optimized lab environment."
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
    condition     = output.cluster_name == aws_eks_cluster.this.name
    error_message = "The module must expose the EKS cluster name as an output."
  }

  assert {
    condition     = output.node_group_name == aws_eks_node_group.this.node_group_name
    error_message = "The module must expose the managed node group name as an output."
  }
}
