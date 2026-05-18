terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

locals {
  cluster_name    = "${var.project_name}-${var.environment}"
  node_group_name = "${local.cluster_name}-spot"

  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Owner       = var.owner
      Module      = "eks"
    },
    var.default_tags
  )
}

data "aws_iam_policy_document" "eks_cluster_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

data "aws_iam_policy_document" "eks_node_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "cluster" {
  name               = "${local.cluster_name}-cluster-role"
  assume_role_policy = data.aws_iam_policy_document.eks_cluster_assume_role.json

  tags = merge(
    local.common_tags,
    {
      Name = "${local.cluster_name}-cluster-role"
      Role = "eks-cluster"
    }
  )
}

resource "aws_iam_role_policy_attachment" "cluster_policy" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role" "node" {
  name               = "${local.cluster_name}-node-role"
  assume_role_policy = data.aws_iam_policy_document.eks_node_assume_role.json

  tags = merge(
    local.common_tags,
    {
      Name = "${local.cluster_name}-node-role"
      Role = "eks-node"
    }
  )
}

resource "aws_iam_role_policy_attachment" "node_worker_policy" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "node_cni_policy" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "node_ecr_policy" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "node_ebs_csi_policy" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

resource "aws_eks_cluster" "this" {
  name     = local.cluster_name
  role_arn = aws_iam_role.cluster.arn
  version  = var.kubernetes_version

  access_config {
    authentication_mode = var.authentication_mode
  }

  vpc_config {
    subnet_ids              = var.cluster_subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = false
  }

  depends_on = [
    aws_iam_role_policy_attachment.cluster_policy,
  ]

  tags = merge(
    local.common_tags,
    {
      Name = local.cluster_name
    }
  )
}

data "aws_eks_addon_version" "coredns" {
  addon_name         = "coredns"
  kubernetes_version = aws_eks_cluster.this.version
  most_recent        = true
}

resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "vpc-cni"
  configuration_values        = jsonencode({ enableNetworkPolicy = "true" })
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [
    aws_eks_cluster.this,
  ]

  tags = merge(
    local.common_tags,
    {
      Name = "${local.cluster_name}-vpc-cni"
    }
  )
}

resource "aws_security_group_rule" "cluster_private_endpoint_ingress" {
  for_each = toset(var.cluster_private_endpoint_access_cidrs)

  type              = "ingress"
  security_group_id = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
  protocol          = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_blocks       = [each.value]
  description       = "Allow private EKS API endpoint access from ${each.value}"
}

resource "aws_launch_template" "node_group" {
  name_prefix            = "${local.node_group_name}-"
  update_default_version = true

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      delete_on_termination = true
      encrypted             = true
      volume_size           = var.node_group.disk_size_gb
      volume_type           = "gp3"
    }
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  tag_specifications {
    resource_type = "instance"

    tags = merge(
      local.common_tags,
      {
        Name = local.node_group_name
        Role = "eks-node"
      }
    )
  }

  tag_specifications {
    resource_type = "volume"

    tags = merge(
      local.common_tags,
      {
        Name = "${local.node_group_name}-volume"
        Role = "eks-node"
      }
    )
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${local.node_group_name}-launch-template"
    }
  )
}

resource "aws_eks_node_group" "this" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = local.node_group_name
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.node_subnet_ids
  version         = var.kubernetes_version
  ami_type        = var.node_ami_type
  capacity_type   = "SPOT"
  instance_types  = var.node_group.instance_types

  scaling_config {
    desired_size = var.node_group.desired_size
    min_size     = var.node_group.min_size
    max_size     = var.node_group.max_size
  }

  launch_template {
    id      = aws_launch_template.node_group.id
    version = aws_launch_template.node_group.latest_version
  }

  depends_on = [
    aws_eks_addon.vpc_cni,
    aws_iam_role_policy_attachment.node_worker_policy,
    aws_iam_role_policy_attachment.node_cni_policy,
    aws_iam_role_policy_attachment.node_ecr_policy,
  ]

  tags = merge(
    local.common_tags,
    {
      Name = local.node_group_name
    }
  )
}

resource "aws_eks_addon" "coredns" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "coredns"
  addon_version               = data.aws_eks_addon_version.coredns.version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [
    aws_eks_node_group.this,
  ]

  tags = merge(
    local.common_tags,
    {
      Name = "${local.cluster_name}-coredns"
    }
  )
}

resource "aws_eks_addon" "ebs_csi_driver" {
  cluster_name = aws_eks_cluster.this.name
  addon_name   = "aws-ebs-csi-driver"

  depends_on = [
    aws_eks_node_group.this,
    aws_iam_role_policy_attachment.node_ebs_csi_policy,
  ]

  tags = merge(
    local.common_tags,
    {
      Name = "${local.cluster_name}-ebs-csi-driver"
    }
  )
}
# 클러스터에 등록
resource "aws_eks_access_entry" "this" {
  for_each = var.access_entries

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.value.principal_arn
  type          = "STANDARD"
  depends_on = [
    aws_eks_cluster.this
  ]
}

# 등록된 신분에 실제 권한 정책 연결
resource "aws_eks_access_policy_association" "this" {
  for_each = {
    for pair in flatten([
      for name, entry in var.access_entries : [
        for policy_name, policy in entry.policy_associations : {
          entry_name  = name
          policy_name = policy_name
          principal   = entry.principal_arn
          policy_arn  = policy.policy_arn
          scope       = policy.access_scope
        }
      ]
    ]) : "${pair.entry_name}-${pair.policy_name}" => pair
  }

  cluster_name  = aws_eks_cluster.this.name
  policy_arn    = each.value.policy_arn
  principal_arn = each.value.principal

  access_scope {
    type       = each.value.scope.type
    namespaces = lookup(each.value.scope, "namespaces", null)
  }
  depends_on = [
    aws_eks_access_entry.this
  ]
}
