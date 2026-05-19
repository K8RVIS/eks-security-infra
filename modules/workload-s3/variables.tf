output "bucket_name" {
  description = "Workload S3 bucket name."
  value       = aws_s3_bucket.this.bucket
}

output "bucket_arn" {
  description = "Workload S3 bucket ARN."
  value       = aws_s3_bucket.this.arn
}

output "policy_arn" {
  description = "IAM policy ARN for workload S3 access."
  value       = aws_iam_policy.workload_s3_access.arn
}
