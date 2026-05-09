output "repository_urls" {
  description = "Map of short repository name to full ECR repository URL."
  value       = { for k, v in aws_ecr_repository.this : k => v.repository_url }
}

output "repository_arns" {
  description = "Map of short repository name to ECR repository ARN."
  value       = { for k, v in aws_ecr_repository.this : k => v.arn }
}

output "registry_id" {
  description = "ECR registry ID (12-digit AWS account ID)."
  value       = data.aws_caller_identity.current.account_id
}

output "kms_key_arn" {
  description = "ARN of the KMS key used to encrypt ECR repositories."
  value       = aws_kms_key.ecr.arn
}

output "kms_key_id" {
  description = "ID of the KMS key used to encrypt ECR repositories."
  value       = aws_kms_key.ecr.key_id
}