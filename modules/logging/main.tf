terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

locals {
  eks_log_group_name        = "/aws/eks/${var.cluster_name}/cluster"
  cloudtrail_log_group_name = "/aws/cloudtrail/${var.cluster_name}"
  trail_name                = "${var.cluster_name}-trail"
  metric_namespace          = "${var.project_name}/EKSSecurity"

  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Owner       = var.owner
      Module      = "logging"
    },
    var.default_tags
  )
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ============================================================
# CloudWatch Log Groups
# ============================================================

resource "aws_cloudwatch_log_group" "eks_cluster" {
  name              = local.eks_log_group_name
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, {
    Name = local.eks_log_group_name
    Type = "eks-control-plane"
  })
}

resource "aws_cloudwatch_log_group" "cloudtrail" {
  name              = local.cloudtrail_log_group_name
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, {
    Name = local.cloudtrail_log_group_name
    Type = "cloudtrail"
  })
}

# ============================================================
# SNS Topic for Security Alerts
# ============================================================

resource "aws_sns_topic" "security_alerts" {
  name = "${var.cluster_name}-security-alerts"

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-security-alerts"
  })
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.alert_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.security_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# ============================================================
# S3 Bucket for CloudTrail Logs
# ============================================================

resource "aws_s3_bucket" "cloudtrail" {
  bucket        = "${var.project_name}-${var.environment}-cloudtrail-${data.aws_caller_identity.current.account_id}"
  force_destroy = var.environment != "prod"

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-cloudtrail"
    Type = "cloudtrail-logs"
  })
}

resource "aws_s3_bucket_versioning" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "cloudtrail" {
  bucket                  = aws_s3_bucket.cloudtrail.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  rule {
    id     = "expire-old-logs"
    status = "Enabled"

    filter {
      prefix = ""
    }

    expiration {
      days = var.cloudtrail_s3_retention_days
    }
  }
}

data "aws_iam_policy_document" "cloudtrail_s3" {
  statement {
    sid    = "AWSCloudTrailAclCheck"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.cloudtrail.arn]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = ["arn:aws:cloudtrail:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:trail/${local.trail_name}"]
    }
  }

  statement {
    sid    = "AWSCloudTrailWrite"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.cloudtrail.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"]

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = ["arn:aws:cloudtrail:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:trail/${local.trail_name}"]
    }
  }
}

resource "aws_s3_bucket_policy" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  policy = data.aws_iam_policy_document.cloudtrail_s3.json

  depends_on = [aws_s3_bucket_public_access_block.cloudtrail]
}

# ============================================================
# IAM Role: CloudTrail → CloudWatch Logs
# ============================================================

data "aws_iam_policy_document" "cloudtrail_assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "cloudtrail_cloudwatch" {
  name               = "${var.cluster_name}-cloudtrail-cw-role"
  assume_role_policy = data.aws_iam_policy_document.cloudtrail_assume_role.json

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-cloudtrail-cw-role"
  })
}

data "aws_iam_policy_document" "cloudtrail_cloudwatch_logs" {
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["${aws_cloudwatch_log_group.cloudtrail.arn}:*"]
  }
}

resource "aws_iam_role_policy" "cloudtrail_cloudwatch" {
  name   = "cloudtrail-cloudwatch-logs"
  role   = aws_iam_role.cloudtrail_cloudwatch.id
  policy = data.aws_iam_policy_document.cloudtrail_cloudwatch_logs.json
}

# ============================================================
# CloudTrail
# ============================================================

resource "aws_cloudtrail" "eks_audit" {
  name                          = local.trail_name
  s3_bucket_name                = aws_s3_bucket.cloudtrail.id
  include_global_service_events = true
  is_multi_region_trail         = false
  enable_log_file_validation    = true

  cloud_watch_logs_group_arn = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
  cloud_watch_logs_role_arn  = aws_iam_role.cloudtrail_cloudwatch.arn

  event_selector {
    read_write_type           = "All"
    include_management_events = true
  }

  depends_on = [
    aws_s3_bucket_policy.cloudtrail,
    aws_iam_role_policy.cloudtrail_cloudwatch,
  ]

  tags = merge(local.common_tags, {
    Name = local.trail_name
  })
}

# ============================================================
# CloudWatch Metric Filters + Alarms (EKS Audit Log Group)
# ============================================================

# 1. Unauthorized API Calls (401 / 403)
resource "aws_cloudwatch_metric_filter" "unauthorized_api_calls" {
  name           = "${var.cluster_name}-unauthorized-api-calls"
  log_group_name = aws_cloudwatch_log_group.eks_cluster.name
  pattern        = "{ $.responseStatus.code = 401 || $.responseStatus.code = 403 }"

  metric_transformation {
    name      = "UnauthorizedAPICalls"
    namespace = local.metric_namespace
    value     = "1"
    unit      = "Count"
  }
}

resource "aws_cloudwatch_metric_alarm" "unauthorized_api_calls" {
  alarm_name          = "${var.cluster_name}-unauthorized-api-calls"
  alarm_description   = "EKS API 401/403 응답이 5분 내 10건 초과 — 비정상 접근 시도 가능성"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "UnauthorizedAPICalls"
  namespace           = local.metric_namespace
  period              = 300
  statistic           = "Sum"
  threshold           = 10
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.security_alerts.arn]
  ok_actions          = [aws_sns_topic.security_alerts.arn]

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-unauthorized-api-calls-alarm"
  })
}

# 2. Pod exec 이벤트 탐지 (kubectl exec)
resource "aws_cloudwatch_metric_filter" "pod_exec" {
  name           = "${var.cluster_name}-pod-exec"
  log_group_name = aws_cloudwatch_log_group.eks_cluster.name
  pattern        = "{ $.objectRef.subresource = \"exec\" }"

  metric_transformation {
    name      = "PodExecEvents"
    namespace = local.metric_namespace
    value     = "1"
    unit      = "Count"
  }
}

resource "aws_cloudwatch_metric_alarm" "pod_exec" {
  alarm_name          = "${var.cluster_name}-pod-exec"
  alarm_description   = "컨테이너 exec 접속 이벤트 감지 — kubectl exec 등 내부 접근 시도"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "PodExecEvents"
  namespace           = local.metric_namespace
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.security_alerts.arn]

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-pod-exec-alarm"
  })
}

# 3. Secret 대량 접근 탐지
resource "aws_cloudwatch_metric_filter" "secret_access" {
  name           = "${var.cluster_name}-secret-access"
  log_group_name = aws_cloudwatch_log_group.eks_cluster.name
  pattern        = "{ $.objectRef.resource = \"secrets\" && ($.verb = \"get\" || $.verb = \"list\" || $.verb = \"watch\") }"

  metric_transformation {
    name      = "SecretAccessEvents"
    namespace = local.metric_namespace
    value     = "1"
    unit      = "Count"
  }
}

resource "aws_cloudwatch_metric_alarm" "secret_access" {
  alarm_name          = "${var.cluster_name}-secret-access"
  alarm_description   = "Kubernetes Secret 접근이 5분 내 20건 초과 — 자격증명 탈취 시도 가능성"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "SecretAccessEvents"
  namespace           = local.metric_namespace
  period              = 300
  statistic           = "Sum"
  threshold           = 20
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.security_alerts.arn]

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-secret-access-alarm"
  })
}

# 4. RBAC 권한 변경 탐지
resource "aws_cloudwatch_metric_filter" "rbac_changes" {
  name           = "${var.cluster_name}-rbac-changes"
  log_group_name = aws_cloudwatch_log_group.eks_cluster.name
  pattern        = "{ ($.objectRef.resource = \"clusterroles\" || $.objectRef.resource = \"clusterrolebindings\" || $.objectRef.resource = \"roles\" || $.objectRef.resource = \"rolebindings\") && ($.verb = \"create\" || $.verb = \"update\" || $.verb = \"patch\" || $.verb = \"delete\") }"

  metric_transformation {
    name      = "RBACChangeEvents"
    namespace = local.metric_namespace
    value     = "1"
    unit      = "Count"
  }
}

resource "aws_cloudwatch_metric_alarm" "rbac_changes" {
  alarm_name          = "${var.cluster_name}-rbac-changes"
  alarm_description   = "Kubernetes RBAC 정책 변경 감지 — Role/ClusterRole 변경은 권한 상승 시도일 수 있음"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "RBACChangeEvents"
  namespace           = local.metric_namespace
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.security_alerts.arn]

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-rbac-changes-alarm"
  })
}
