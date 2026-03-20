terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Remote state — keeps tfstate out of the repo and enables team collaboration.
  # Bucket and table must be created once manually (bootstrap) before first apply.
  backend "s3" {
    bucket         = "sentinellink-tfstate"
    key            = "sentinellink/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "sentinellink-tfstate-lock"
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "SentinelLink"
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}
