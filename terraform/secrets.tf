# ---------------------------------------------------------------------------
# Secrets Manager — DB credentials stored securely, never in plaintext.
#
# The FastAPI app reads DB_SECRET_ARN from its pod environment, then calls
# secretsmanager:GetSecretValue at startup to obtain the connection string.
# The IRSA role (iam.tf) grants the pod permission to call that API.
# ---------------------------------------------------------------------------

# Generate a strong random password (Terraform manages rotation)
resource "random_password" "db_password" {
  length           = 32
  special          = true
  override_special = "!#$%^&*()-_=+[]{}|;:,.<>?"
  min_special      = 2
  min_upper        = 4
  min_lower        = 4
  min_numeric      = 4
}

# Store credentials as a structured JSON secret
resource "aws_secretsmanager_secret" "db_credentials" {
  name                    = "sentinellink/db-credentials"
  description             = "SentinelLink RDS PostgreSQL master credentials"
  recovery_window_in_days = 7   # Soft-delete — allows recovery if accidentally deleted

  tags = { Name = "sentinellink-db-credentials" }
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id

  secret_string = jsonencode({
    username = var.rds_master_username
    password = random_password.db_password.result
    host     = aws_db_instance.postgres.address
    port     = aws_db_instance.postgres.port
    dbname   = aws_db_instance.postgres.db_name
  })
}
