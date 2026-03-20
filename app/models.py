"""
models.py
---------
SQLAlchemy ORM models for SentinelLink.

An Asset represents any tracked infrastructure resource (S3 bucket, RDS
instance, EC2, EKS cluster, …).  The `is_public` flag is enforced to False
at the application layer; any drift will be surfaced by the monitoring stack.
"""

import uuid
from datetime import datetime, timezone

from sqlalchemy import Boolean, Column, DateTime, Enum, String, Text
from sqlalchemy.dialects.postgresql import UUID

from database import Base  # noqa: E402  (resolved at runtime)

import enum


class AssetType(str, enum.Enum):
    S3_BUCKET = "S3_BUCKET"
    RDS_INSTANCE = "RDS_INSTANCE"
    EC2_INSTANCE = "EC2_INSTANCE"
    EKS_CLUSTER = "EKS_CLUSTER"
    SECRETS_MANAGER = "SECRETS_MANAGER"
    IAM_ROLE = "IAM_ROLE"
    VPC = "VPC"
    OTHER = "OTHER"


class Environment(str, enum.Enum):
    PRODUCTION = "production"
    STAGING = "staging"
    DEVELOPMENT = "development"


class Asset(Base):
    __tablename__ = "assets"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4, index=True)
    name = Column(String(255), nullable=False, index=True)
    asset_type = Column(Enum(AssetType), nullable=False)
    environment = Column(Enum(Environment), nullable=False)
    region = Column(String(64), nullable=False)
    owner = Column(String(255), nullable=False)

    # Security posture fields
    is_encrypted = Column(Boolean, nullable=False, default=True)
    is_public = Column(Boolean, nullable=False, default=False)  # Must always be False

    description = Column(Text, nullable=True)
    arn = Column(String(512), nullable=True, unique=True)  # AWS ARN if applicable

    created_at = Column(
        DateTime(timezone=True),
        nullable=False,
        default=lambda: datetime.now(timezone.utc),
    )
    updated_at = Column(
        DateTime(timezone=True),
        nullable=False,
        default=lambda: datetime.now(timezone.utc),
        onupdate=lambda: datetime.now(timezone.utc),
    )
