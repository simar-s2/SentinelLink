# ---------------------------------------------------------------------------
# RDS — Encrypted PostgreSQL instance with zero public exposure.
#
# Security controls applied:
#   1. storage_encrypted = true (AES-256 via AWS-managed key)
#   2. publicly_accessible = false — no public endpoint
#   3. Placed in private subnets only
#   4. Security group allows inbound 5432 only from the EKS pod SG
#   5. Credentials stored in Secrets Manager (see secrets.tf), never in tfvars
#   6. Multi-AZ enabled in production for high availability
#   7. Automated backups with 7-day retention
#   8. Deletion protection on — prevents accidental `terraform destroy`
# ---------------------------------------------------------------------------

# ── Subnet group: private subnets only ──────────────────────────────────────
resource "aws_db_subnet_group" "postgres" {
  name       = "sentinellink-postgres-subnet-group"
  subnet_ids = aws_subnet.private[*].id
  tags       = { Name = "sentinellink-postgres-subnet-group" }
}

# ── Security group: allow 5432 only from EKS pod security group ─────────────
resource "aws_security_group" "rds" {
  name        = "sentinellink-rds-sg"
  description = "Allow PostgreSQL access only from EKS pods"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "PostgreSQL from EKS pods"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.eks_pods.id]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "sentinellink-rds-sg" }
}

# Minimal SG representing EKS pods — referenced in the ingress rule above.
# In a real deployment this is managed by the EKS module; here it's defined
# so Terraform has a concrete resource to reference.
resource "aws_security_group" "eks_pods" {
  name        = "sentinellink-eks-pods-sg"
  description = "Security group assigned to SentinelLink pods on EKS"
  vpc_id      = aws_vpc.main.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "sentinellink-eks-pods-sg" }
}

# ── RDS instance ─────────────────────────────────────────────────────────────
resource "aws_db_instance" "postgres" {
  identifier        = "sentinellink-postgres"
  engine            = "postgres"
  engine_version    = "16.2"
  instance_class    = var.rds_instance_class
  allocated_storage = 20
  storage_type      = "gp3"

  db_name  = var.rds_db_name
  username = var.rds_master_username
  # Password is generated in secrets.tf and injected via Secrets Manager.
  # We reference the random_password resource directly so Terraform manages it.
  password = random_password.db_password.result

  # Encryption
  storage_encrypted = true   # AES-256 using AWS-managed key

  # Network — strictly private
  db_subnet_group_name   = aws_db_subnet_group.postgres.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false   # No public endpoint

  # Availability
  multi_az = var.environment == "production" ? true : false

  # Backups
  backup_retention_period = 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "mon:04:00-mon:05:00"

  # Safety
  deletion_protection       = true
  skip_final_snapshot       = false
  final_snapshot_identifier = "sentinellink-postgres-final-snapshot"

  # Performance Insights for query-level observability
  performance_insights_enabled = true

  tags = { Name = "sentinellink-postgres" }
}
