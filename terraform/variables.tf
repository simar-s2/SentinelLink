variable "aws_region" {
  description = "AWS region to deploy all resources into."
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Deployment environment (production | staging | development)."
  type        = string
  default     = "production"

  validation {
    condition     = contains(["production", "staging", "development"], var.environment)
    error_message = "environment must be one of: production, staging, development."
  }
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets (one per AZ). Data tier only — no public subnets."
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "availability_zones" {
  description = "AZs to spread subnets across."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "s3_bucket_name" {
  description = "Globally unique name for the asset-registry S3 bucket."
  type        = string
  default     = "sentinellink-asset-registry"
}

variable "rds_instance_class" {
  description = "RDS instance type."
  type        = string
  default     = "db.t3.micro"
}

variable "rds_db_name" {
  description = "Name of the PostgreSQL database to create."
  type        = string
  default     = "sentinellink"
}

variable "rds_master_username" {
  description = "RDS master username."
  type        = string
  default     = "sentinellink_admin"
  sensitive   = true
}

variable "eks_oidc_provider_arn" {
  description = "ARN of the EKS cluster OIDC provider (used for IRSA trust policy)."
  type        = string
  # No default — must be supplied when applying against a real cluster.
}

variable "eks_oidc_provider_url" {
  description = "URL of the EKS cluster OIDC provider (without https://)."
  type        = string
}

variable "k8s_namespace" {
  description = "Kubernetes namespace where SentinelLink pods run."
  type        = string
  default     = "sentinellink"
}

variable "k8s_service_account_name" {
  description = "Kubernetes ServiceAccount name used by the pods."
  type        = string
  default     = "sentinellink-sa"
}
