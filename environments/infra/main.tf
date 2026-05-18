module "vpc" {
  source = "../../modules/vpc"

  project_name          = var.project_name
  environment           = var.environment
  aws_region            = var.aws_region
  owner                 = var.owner
  vpc_cidr              = var.vpc_cidr
  availability_zones    = var.availability_zones
  public_subnet_cidrs   = var.public_subnet_cidrs
  private_subnet_cidrs  = var.private_subnet_cidrs
  fck_nat_instance_type = var.fck_nat_instance_type
  default_tags          = var.default_tags
}

locals {
  eks_cluster_name             = "${var.project_name}-${var.environment}"
  break_glass_role_name        = "${var.project_name}-${var.environment}-break-glass"
  break_glass_alert_topic_name = "${var.project_name}-${var.environment}-break-glass-alerts"
  break_glass_state_table_name = "${var.project_name}-${var.environment}-break-glass-grants"
  break_glass_scheduler_group  = "${var.project_name}-${var.environment}-break-glass"
  break_glass_revoker_name     = "${var.project_name}-${var.environment}-break-glass-revoker"
  eks_audit_log_group_name     = "/aws/eks/${local.eks_cluster_name}/cluster"
  break_glass_alarm_period     = var.break_glass_alarm_evaluation_period_minutes * 60
}

resource "aws_cloudwatch_log_group" "eks_cluster" {
  name              = local.eks_audit_log_group_name
  retention_in_days = var.eks_control_plane_log_retention_days

  tags = merge(
    var.default_tags,
    {
      Name        = local.eks_audit_log_group_name
      Environment = var.environment
      Purpose     = "eks-control-plane-logs"
    }
  )
}

data "aws_caller_identity" "current" {}

module "eks" {
  source = "../../modules/eks"

  project_name                          = var.project_name
  environment                           = var.environment
  owner                                 = var.owner
  cluster_subnet_ids                    = module.vpc.private_subnet_ids
  node_subnet_ids                       = module.vpc.private_subnet_ids
  cluster_private_endpoint_access_cidrs = var.cluster_private_endpoint_access_cidrs
  kubernetes_version                    = var.kubernetes_version
  node_ami_type                         = var.node_ami_type
  node_group                            = var.node_group
  default_tags                          = var.default_tags
  enabled_cluster_log_types             = var.enabled_cluster_log_types

  authentication_mode = "API_AND_CONFIG_MAP"
  access_entries = {
    for name, arn in var.user_iam_arn : name => {
      principal_arn = arn
      policy_associations = {
        admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
    if trimspace(arn) != ""
  }

  depends_on = [
    aws_cloudwatch_log_group.eks_cluster,
  ]
}

data "aws_iam_policy_document" "break_glass_assume_role" {
  count = var.break_glass_enabled ? 1 : 0

  statement {
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = var.break_glass_trusted_principal_arns
    }

    actions = ["sts:AssumeRole"]

    dynamic "condition" {
      for_each = var.break_glass_require_mfa ? [1] : []

      content {
        test     = "Bool"
        variable = "aws:MultiFactorAuthPresent"
        values   = ["true"]
      }
    }
  }
}

data "aws_iam_policy_document" "break_glass_permissions" {
  count = var.break_glass_enabled ? 1 : 0

  statement {
    effect = "Allow"

    actions = [
      "eks:DescribeCluster",
    ]

    resources = [
      module.eks.cluster_arn,
    ]
  }
}

resource "aws_iam_role" "break_glass" {
  count = var.break_glass_enabled ? 1 : 0

  name               = local.break_glass_role_name
  description        = "Emergency EKS access role. Every AssumeRole event is monitored."
  assume_role_policy = data.aws_iam_policy_document.break_glass_assume_role[0].json

  tags = merge(
    var.default_tags,
    {
      Name        = local.break_glass_role_name
      Environment = var.environment
      Purpose     = "break-glass"
    }
  )
}

resource "aws_iam_role_policy" "break_glass_permissions" {
  count = var.break_glass_enabled ? 1 : 0

  name   = "${local.break_glass_role_name}-eks-describe"
  role   = aws_iam_role.break_glass[0].id
  policy = data.aws_iam_policy_document.break_glass_permissions[0].json
}

resource "aws_dynamodb_table" "break_glass_grants" {
  count = var.break_glass_enabled ? 1 : 0

  name         = local.break_glass_state_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "grant_id"

  attribute {
    name = "grant_id"
    type = "S"
  }

  ttl {
    attribute_name = "ttl_epoch"
    enabled        = true
  }

  tags = merge(
    var.default_tags,
    {
      Name        = local.break_glass_state_table_name
      Environment = var.environment
      Purpose     = "break-glass-jit-state"
    }
  )
}

resource "aws_scheduler_schedule_group" "break_glass" {
  count = var.break_glass_enabled ? 1 : 0

  name = local.break_glass_scheduler_group

  tags = merge(
    var.default_tags,
    {
      Name        = local.break_glass_scheduler_group
      Environment = var.environment
      Purpose     = "break-glass-auto-revoke"
    }
  )
}

data "aws_iam_policy_document" "break_glass_revoker_assume_role" {
  count = var.break_glass_enabled ? 1 : 0

  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

data "aws_iam_policy_document" "break_glass_revoker_permissions" {
  count = var.break_glass_enabled ? 1 : 0

  statement {
    effect = "Allow"

    actions = [
      "eks:DescribeAccessEntry",
      "eks:DeleteAccessEntry",
      "eks:DisassociateAccessPolicy",
      "eks:ListAssociatedAccessPolicies",
    ]

    resources = [
      module.eks.cluster_arn,
    ]
  }

  statement {
    effect = "Allow"

    actions = [
      "dynamodb:GetItem",
      "dynamodb:UpdateItem",
    ]

    resources = [
      aws_dynamodb_table.break_glass_grants[0].arn,
    ]
  }

  statement {
    effect = "Allow"

    actions = [
      "sns:Publish",
    ]

    resources = [
      aws_sns_topic.break_glass_alerts[0].arn,
    ]
  }

  statement {
    effect = "Allow"

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]

    resources = ["*"]
  }
}

resource "aws_iam_role" "break_glass_revoker" {
  count = var.break_glass_enabled ? 1 : 0

  name               = "${local.break_glass_revoker_name}-lambda"
  assume_role_policy = data.aws_iam_policy_document.break_glass_revoker_assume_role[0].json

  tags = merge(
    var.default_tags,
    {
      Name        = "${local.break_glass_revoker_name}-lambda"
      Environment = var.environment
      Purpose     = "break-glass-auto-revoke"
    }
  )
}

resource "aws_iam_role_policy" "break_glass_revoker" {
  count = var.break_glass_enabled ? 1 : 0

  name   = "${local.break_glass_revoker_name}-permissions"
  role   = aws_iam_role.break_glass_revoker[0].id
  policy = data.aws_iam_policy_document.break_glass_revoker_permissions[0].json
}

data "archive_file" "break_glass_revoker" {
  count = var.break_glass_enabled ? 1 : 0

  type        = "zip"
  source_file = "${path.module}/../../lambda/break_glass_revoker.py"
  output_path = "${path.module}/.terraform/${local.break_glass_revoker_name}.zip"
}

resource "aws_lambda_function" "break_glass_revoker" {
  count = var.break_glass_enabled ? 1 : 0

  function_name    = local.break_glass_revoker_name
  role             = aws_iam_role.break_glass_revoker[0].arn
  handler          = "break_glass_revoker.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.break_glass_revoker[0].output_path
  source_code_hash = data.archive_file.break_glass_revoker[0].output_base64sha256
  timeout          = 60

  environment {
    variables = {
      BREAK_GLASS_TABLE_NAME = aws_dynamodb_table.break_glass_grants[0].name
      SNS_TOPIC_ARN          = aws_sns_topic.break_glass_alerts[0].arn
      AWS_REGION_NAME        = var.aws_region
    }
  }

  tags = merge(
    var.default_tags,
    {
      Name        = local.break_glass_revoker_name
      Environment = var.environment
      Purpose     = "break-glass-auto-revoke"
    }
  )
}

data "aws_iam_policy_document" "break_glass_scheduler_assume_role" {
  count = var.break_glass_enabled ? 1 : 0

  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["scheduler.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

data "aws_iam_policy_document" "break_glass_scheduler_permissions" {
  count = var.break_glass_enabled ? 1 : 0

  statement {
    effect = "Allow"

    actions = [
      "lambda:InvokeFunction",
    ]

    resources = [
      aws_lambda_function.break_glass_revoker[0].arn,
    ]
  }
}

resource "aws_iam_role" "break_glass_scheduler" {
  count = var.break_glass_enabled ? 1 : 0

  name               = "${local.break_glass_revoker_name}-scheduler"
  assume_role_policy = data.aws_iam_policy_document.break_glass_scheduler_assume_role[0].json

  tags = merge(
    var.default_tags,
    {
      Name        = "${local.break_glass_revoker_name}-scheduler"
      Environment = var.environment
      Purpose     = "break-glass-auto-revoke"
    }
  )
}

resource "aws_iam_role_policy" "break_glass_scheduler" {
  count = var.break_glass_enabled ? 1 : 0

  name   = "${local.break_glass_revoker_name}-scheduler"
  role   = aws_iam_role.break_glass_scheduler[0].id
  policy = data.aws_iam_policy_document.break_glass_scheduler_permissions[0].json
}

resource "aws_sns_topic" "break_glass_alerts" {
  count = var.break_glass_enabled ? 1 : 0

  name = local.break_glass_alert_topic_name

  tags = merge(
    var.default_tags,
    {
      Name        = local.break_glass_alert_topic_name
      Environment = var.environment
      Purpose     = "break-glass-alerting"
    }
  )
}

resource "aws_sns_topic_subscription" "break_glass_email" {
  for_each = var.break_glass_enabled ? toset(var.break_glass_alert_email_addresses) : toset([])

  topic_arn = aws_sns_topic.break_glass_alerts[0].arn
  protocol  = "email"
  endpoint  = each.value
}

resource "aws_cloudwatch_event_rule" "break_glass_assume_role" {
  count = var.break_glass_enabled ? 1 : 0

  name        = "${local.break_glass_role_name}-assume-role"
  description = "Detect STS AssumeRole usage of the EKS break-glass role."

  event_pattern = jsonencode({
    source      = ["aws.sts"]
    detail-type = ["AWS API Call via CloudTrail"]
    detail = {
      eventSource = ["sts.amazonaws.com"]
      eventName   = ["AssumeRole"]
      requestParameters = {
        roleArn = [aws_iam_role.break_glass[0].arn]
      }
    }
  })
}

resource "aws_cloudwatch_event_target" "break_glass_assume_role_sns" {
  count = var.break_glass_enabled ? 1 : 0

  rule      = aws_cloudwatch_event_rule.break_glass_assume_role[0].name
  target_id = "sns"
  arn       = aws_sns_topic.break_glass_alerts[0].arn
}

resource "aws_sns_topic_policy" "break_glass_alerts" {
  count = var.break_glass_enabled ? 1 : 0

  arn = aws_sns_topic.break_glass_alerts[0].arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowAccountTopicManagement"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action = [
          "sns:GetTopicAttributes",
          "sns:ListSubscriptionsByTopic",
          "sns:Publish",
          "sns:Subscribe",
        ]
        Resource = aws_sns_topic.break_glass_alerts[0].arn
      },
      {
        Sid    = "AllowEventBridgePublish"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action   = "sns:Publish"
        Resource = aws_sns_topic.break_glass_alerts[0].arn
      },
      {
        Sid    = "AllowCloudWatchPublish"
        Effect = "Allow"
        Principal = {
          Service = "cloudwatch.amazonaws.com"
        }
        Action   = "sns:Publish"
        Resource = aws_sns_topic.break_glass_alerts[0].arn
      },
    ]
  })
}

resource "aws_cloudwatch_log_metric_filter" "high_risk_kubernetes_api" {
  count = var.break_glass_enabled ? 1 : 0

  name           = "${module.eks.cluster_name}-high-risk-kubernetes-api"
  log_group_name = local.eks_audit_log_group_name
  pattern        = "{ (($.verb = \"create\") || ($.verb = \"update\") || ($.verb = \"patch\") || ($.verb = \"delete\")) && (($.objectRef.resource = \"secrets\") || ($.objectRef.resource = \"clusterroles\") || ($.objectRef.resource = \"clusterrolebindings\") || ($.objectRef.resource = \"roles\") || ($.objectRef.resource = \"rolebindings\") || ($.objectRef.resource = \"serviceaccounts\") || ($.objectRef.resource = \"pods\") || ($.objectRef.subresource = \"exec\")) }"

  metric_transformation {
    name      = "HighRiskKubernetesApiRequestCount"
    namespace = "EKS/${module.eks.cluster_name}/Audit"
    value     = "1"
  }

  depends_on = [
    module.eks,
    aws_cloudwatch_log_group.eks_cluster,
  ]
}

resource "aws_cloudwatch_metric_alarm" "high_risk_kubernetes_api" {
  count = var.break_glass_enabled ? 1 : 0

  alarm_name          = "${module.eks.cluster_name}-high-risk-kubernetes-api"
  alarm_description   = "High-risk Kubernetes API request observed in EKS audit logs."
  namespace           = "EKS/${module.eks.cluster_name}/Audit"
  metric_name         = "HighRiskKubernetesApiRequestCount"
  statistic           = "Sum"
  period              = local.break_glass_alarm_period
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.break_glass_alerts[0].arn]
}

module "ecr" {
  source = "../../modules/ecr"

  project_name         = var.project_name
  environment          = var.environment
  owner                = var.owner
  repository_names     = var.ecr_repository_names
  max_image_count      = var.ecr_max_image_count
  untagged_expiry_days = var.ecr_untagged_expiry_days
  default_tags         = var.default_tags
}
