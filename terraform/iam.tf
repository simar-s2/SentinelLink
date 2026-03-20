# ---------------------------------------------------------------------------
# IAM — IRSA (IAM Roles for Service Accounts)
#
# IRSA lets Kubernetes pods assume an IAM role WITHOUT storing long-lived
# AWS credentials anywhere.  The flow is:
#   1. EKS OIDC provider issues a signed JWT for the pod's ServiceAccount.
#   2. The pod presents that JWT to AWS STS AssumeRoleWithWebIdentity.
#   3. AWS validates the JWT against the OIDC provider, then issues short-lived
#      credentials scoped to this role.
#
# Least-privilege policy grants only what the app actually needs:
#   - secretsmanager:GetSecretValue on the one DB-credentials secret
#   - s3:GetObject / PutObject on the one asset-registry bucket
# ---------------------------------------------------------------------------

# ── Trust policy: only the specific ServiceAccount in the specific namespace ─
data "aws_iam_policy_document" "irsa_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.eks_oidc_provider_arn]
    }

    # Double-condition prevents confused-deputy attacks:
    #   aud  — must be the STS audience
    #   sub  — must be THIS specific ServiceAccount in THIS namespace
    condition {
      test     = "StringEquals"
      variable = "${var.eks_oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.eks_oidc_provider_url}:sub"
      values   = ["system:serviceaccount:${var.k8s_namespace}:${var.k8s_service_account_name}"]
    }
  }
}

resource "aws_iam_role" "sentinellink_irsa" {
  name               = "sentinellink-irsa-role"
  assume_role_policy = data.aws_iam_policy_document.irsa_trust.json
  description        = "IRSA role for SentinelLink pods — least-privilege access to Secrets Manager and S3"

  tags = { Name = "sentinellink-irsa-role" }
}

# ── Permissions policy: Secrets Manager + S3 only ───────────────────────────
data "aws_iam_policy_document" "sentinellink_permissions" {
  # Allow the pod to fetch DB credentials from Secrets Manager
  statement {
    sid    = "ReadDbSecret"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]
    resources = [aws_secretsmanager_secret.db_credentials.arn]
  }

  # Allow the pod to read and write objects in the asset-registry bucket
  statement {
    sid    = "AssetRegistryBucketAccess"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket",
    ]
    resources = [
      aws_s3_bucket.asset_registry.arn,
      "${aws_s3_bucket.asset_registry.arn}/*",
    ]
  }

  # Deny everything else explicitly (defense in depth)
  statement {
    sid       = "DenyAllOtherActions"
    effect    = "Deny"
    actions   = ["s3:*", "secretsmanager:*"]
    resources = ["*"]

    condition {
      test     = "StringNotEquals"
      variable = "aws:ResourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

data "aws_caller_identity" "current" {}

resource "aws_iam_policy" "sentinellink" {
  name        = "sentinellink-pod-policy"
  description = "Least-privilege policy for SentinelLink pods via IRSA"
  policy      = data.aws_iam_policy_document.sentinellink_permissions.json
}

resource "aws_iam_role_policy_attachment" "sentinellink" {
  role       = aws_iam_role.sentinellink_irsa.name
  policy_arn = aws_iam_policy.sentinellink.arn
}
