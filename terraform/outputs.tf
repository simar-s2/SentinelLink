output "s3_bucket_name" {
  description = "Name of the encrypted asset-registry S3 bucket."
  value       = aws_s3_bucket.asset_registry.id
}

output "s3_bucket_arn" {
  description = "ARN of the asset-registry S3 bucket."
  value       = aws_s3_bucket.asset_registry.arn
}

output "rds_endpoint" {
  description = "RDS instance endpoint (host:port). Used by the app to connect."
  value       = aws_db_instance.postgres.endpoint
  sensitive   = true
}

output "rds_db_name" {
  description = "Name of the PostgreSQL database."
  value       = aws_db_instance.postgres.db_name
}

output "db_secret_arn" {
  description = "ARN of the Secrets Manager secret holding RDS credentials."
  value       = aws_secretsmanager_secret.db_credentials.arn
  sensitive   = true
}

output "irsa_role_arn" {
  description = "ARN of the IAM role to annotate on the Kubernetes ServiceAccount (IRSA)."
  value       = aws_iam_role.sentinellink_irsa.arn
}

output "vpc_id" {
  description = "VPC ID."
  value       = aws_vpc.main.id
}

output "private_subnet_ids" {
  description = "List of private subnet IDs (pass to EKS node groups and RDS subnet group)."
  value       = aws_subnet.private[*].id
}
