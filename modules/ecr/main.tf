terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

data "aws_caller_identity" "current" {}

locals {
  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Owner       = var.owner
      Module      = "ecr"
    },
    var.default_tags
  )
}

# ---------------------------------------------------------------------------
# KMS key: ECR repositories are encrypted at rest
# ---------------------------------------------------------------------------
resource "aws_kms_key" "ecr" {
  description             = "KMS key for ${var.project_name} ECR repositories"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-ecr-kms"
  })
}

resource "aws_kms_alias" "ecr" {
  name          = "alias/${var.project_name}-ecr"
  target_key_id = aws_kms_key.ecr.key_id
}

# ---------------------------------------------------------------------------
# ECR repositories
#   - IMMUTABLE tags: once pushed, a tag cannot be overwritten (supply-chain)
#   - scan_on_push: basic scanning as a fallback if Inspector is disabled
# ---------------------------------------------------------------------------
resource "aws_ecr_repository" "this" {
  for_each = toset(var.repository_names)

  name                 = "${var.project_name}/${each.key}"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = aws_kms_key.ecr.arn
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}/${each.key}"
  })
}

# ---------------------------------------------------------------------------
# Lifecycle policy per repository
#   Rule 1 (priority 1): untagged images expire after N days (builder layers)
#   Rule 2 (priority 2): keep only last N images total (rolling cleanup)
# ---------------------------------------------------------------------------
resource "aws_ecr_lifecycle_policy" "this" {
  for_each   = aws_ecr_repository.this
  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after ${var.untagged_expiry_days} days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = var.untagged_expiry_days
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep last ${var.max_image_count} images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = var.max_image_count
        }
        action = { type = "expire" }
      }
    ]
  })
}

# ---------------------------------------------------------------------------
# Amazon Inspector v2 — enable ECR enhanced scanning for this account
#
# Enhanced scanning = Inspector continuously monitors every image in the
# registry against the latest NVD / vendor advisory feeds (CONTINUOUS_SCAN),
# not only at push time. New CVEs discovered after an image was pushed will
# surface automatically as new findings.
# ---------------------------------------------------------------------------
resource "aws_inspector2_enabler" "ecr" {
  account_ids    = [data.aws_caller_identity.current.account_id]
  resource_types = ["ECR"]
}

# Registry-level scanning configuration: switch from BASIC to ENHANCED and
# set CONTINUOUS_SCAN for all project repositories.
resource "aws_ecr_registry_scanning_configuration" "this" {
  scan_type = "ENHANCED"

  rule {
    scan_frequency = "CONTINUOUS_SCAN"

    repository_filter {
      filter      = "${var.project_name}/*"
      filter_type = "WILDCARD"
    }
  }

  # Inspector must be enabled before we can switch the registry to ENHANCED
  depends_on = [aws_inspector2_enabler.ecr]
}

