locals {
  severity_filter = ["CRITICAL", "HIGH"]
}

# ---------------------------------------------------------------------------
# SNS topic — receives Inspector finding alerts
# ---------------------------------------------------------------------------
resource "aws_sns_topic" "inspector_alerts" {
  name = "${var.project_name}-inspector-alerts"
  tags = local.common_tags
}

resource "aws_sns_topic_policy" "inspector_alerts" {
  arn = aws_sns_topic.inspector_alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowEventBridgePublish"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action   = "sns:Publish"
        Resource = aws_sns_topic.inspector_alerts.arn
      }
    ]
  })
}

resource "aws_sns_topic_subscription" "inspector_alerts_email" {
  count     = var.alert_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.inspector_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# ---------------------------------------------------------------------------
# EventBridge rule — triggers on Inspector CRITICAL / HIGH findings
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_event_rule" "inspector_findings" {
  name        = "${var.project_name}-inspector-findings"
  description = "Inspector CRITICAL/HIGH 취약점 발견 시 SNS 알림"

  event_pattern = jsonencode({
    source      = ["aws.inspector2"]
    detail-type = ["Inspector2 Finding"]
    detail = {
      severity = local.severity_filter
      status   = ["ACTIVE"]
      resources = {
        type = ["AWS_ECR_CONTAINER_IMAGE"]
      }
    }
  })

  tags = local.common_tags
}

resource "aws_cloudwatch_event_target" "inspector_to_sns" {
  rule      = aws_cloudwatch_event_rule.inspector_findings.name
  target_id = "InspectorToSNS"
  arn       = aws_sns_topic.inspector_alerts.arn

  input_transformer {
    input_paths = {
      severity    = "$.detail.severity"
      title       = "$.detail.title"
      description = "$.detail.description"
      image_uri   = "$.detail.resources[0].details.awsEcrContainerImage.imageHash"
      account_id  = "$.account"
      region      = "$.region"
    }
    input_template = <<-EOT
      "[Inspector 보안 알림] <severity> 취약점 발견

      제목: <title>
      설명: <description>
      이미지: <image_uri>
      계정: <account_id>
      리전: <region>

      AWS Console에서 Inspector 결과를 확인하고 실제 환경 영향도를 판단하세요."
    EOT
  }
}
