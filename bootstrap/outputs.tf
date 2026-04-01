output "tfstate_bucket_name" {
  description = "S3 bucket name used for Terraform state storage."
  value       = aws_s3_bucket.tfstate.bucket
}

output "tfstate_bucket_arn" {
  description = "S3 bucket ARN used for Terraform state storage."
  value       = aws_s3_bucket.tfstate.arn
}

output "aws_region" {
  description = "AWS region configured for the bootstrap stack."
  value       = var.aws_region
}
