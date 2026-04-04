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

output "github_oidc_provider_arn" {
  description = "ARN of the GitHub Actions OIDC provider."
  value       = aws_iam_openid_connect_provider.github_actions.arn
}

output "github_oidc_provider_url" {
  description = "Issuer URL of the GitHub Actions OIDC provider."
  value       = aws_iam_openid_connect_provider.github_actions.url
}
