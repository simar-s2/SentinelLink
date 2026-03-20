# ---------------------------------------------------------------------------
# S3 — Encrypted asset-registry bucket with zero public exposure.
#
# Security controls applied:
#   1. AES-256 server-side encryption (SSE-S3) by default
#   2. Public access blocked at every level (ACLs, policies, cross-account)
#   3. Bucket policy explicitly denies any s3:PutObject that skips encryption
#   4. Versioning enabled for audit trail / accidental-delete recovery
#   5. Access logging to a separate dedicated log bucket
# ---------------------------------------------------------------------------

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# ── Main asset-registry bucket ───────────────────────────────────────────────
resource "aws_s3_bucket" "asset_registry" {
  bucket        = "${var.s3_bucket_name}-${random_id.bucket_suffix.hex}"
  force_destroy = false   # Protect against accidental terraform destroy

  tags = { Name = "sentinellink-asset-registry" }
}

# Block ALL public access — four toggles must all be true
resource "aws_s3_bucket_public_access_block" "asset_registry" {
  bucket                  = aws_s3_bucket.asset_registry.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Enforce AES-256 encryption at rest for every object
resource "aws_s3_bucket_server_side_encryption_configuration" "asset_registry" {
  bucket = aws_s3_bucket.asset_registry.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# Enable versioning — lets us recover any overwritten/deleted object
resource "aws_s3_bucket_versioning" "asset_registry" {
  bucket = aws_s3_bucket.asset_registry.id
  versioning_configuration { status = "Enabled" }
}

# Bucket policy: deny any upload that does not use server-side encryption
resource "aws_s3_bucket_policy" "deny_unencrypted_uploads" {
  bucket = aws_s3_bucket.asset_registry.id
  # Must wait for the public-access-block to be in place first
  depends_on = [aws_s3_bucket_public_access_block.asset_registry]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyUnencryptedObjectUploads"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.asset_registry.arn}/*"
        Condition = {
          StringNotEquals = {
            "s3:x-amz-server-side-encryption" = "AES256"
          }
        }
      },
      {
        Sid       = "DenyHTTP"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = [
          aws_s3_bucket.asset_registry.arn,
          "${aws_s3_bucket.asset_registry.arn}/*"
        ]
        Condition = {
          Bool = { "aws:SecureTransport" = "false" }
        }
      }
    ]
  })
}

# ── Access log bucket ────────────────────────────────────────────────────────
resource "aws_s3_bucket" "access_logs" {
  bucket        = "sentinellink-access-logs-${random_id.bucket_suffix.hex}"
  force_destroy = false
  tags          = { Name = "sentinellink-access-logs" }
}

resource "aws_s3_bucket_public_access_block" "access_logs" {
  bucket                  = aws_s3_bucket.access_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

resource "aws_s3_bucket_logging" "asset_registry" {
  bucket        = aws_s3_bucket.asset_registry.id
  target_bucket = aws_s3_bucket.access_logs.id
  target_prefix = "s3-access-logs/"
}
