output "eks_log_group_name" {
  description = "CloudWatch Log Group name for EKS control plane logs."
  value       = aws_cloudwatch_log_group.eks_cluster.name
}

output "eks_log_group_arn" {
  description = "CloudWatch Log Group ARN for EKS control plane logs."
  value       = aws_cloudwatch_log_group.eks_cluster.arn
}

output "cloudtrail_log_group_name" {
  description = "CloudWatch Log Group name for CloudTrail."
  value       = aws_cloudwatch_log_group.cloudtrail.name
}

output "cloudtrail_log_group_arn" {
  description = "CloudWatch Log Group ARN for CloudTrail."
  value       = aws_cloudwatch_log_group.cloudtrail.arn
}

output "cloudtrail_arn" {
  description = "ARN of the CloudTrail trail."
  value       = aws_cloudtrail.eks_audit.arn
}

output "cloudtrail_s3_bucket_name" {
  description = "S3 bucket name where CloudTrail logs are stored."
  value       = aws_s3_bucket.cloudtrail.id
}

output "cloudtrail_s3_bucket_arn" {
  description = "S3 bucket ARN for CloudTrail logs."
  value       = aws_s3_bucket.cloudtrail.arn
}

output "security_alerts_sns_topic_arn" {
  description = "SNS topic ARN for security alert notifications."
  value       = aws_sns_topic.security_alerts.arn
}
