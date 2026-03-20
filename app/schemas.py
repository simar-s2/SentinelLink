"""
schemas.py
----------
Pydantic request/response schemas for the Asset resource.
"""

from datetime import datetime
from typing import Optional
from uuid import UUID

from pydantic import BaseModel, Field, field_validator

from models import AssetType, Environment


class AssetBase(BaseModel):
    name: str = Field(..., min_length=1, max_length=255, examples=["prod-assets-bucket"])
    asset_type: AssetType
    environment: Environment
    region: str = Field(..., min_length=1, max_length=64, examples=["us-east-1"])
    owner: str = Field(..., min_length=1, max_length=255, examples=["platform-team"])
    is_encrypted: bool = Field(default=True)
    is_public: bool = Field(default=False)
    description: Optional[str] = None
    arn: Optional[str] = Field(default=None, max_length=512)

    @field_validator("is_public")
    @classmethod
    def reject_public_assets(cls, v: bool) -> bool:
        """Enforce zero public exposure at the schema layer."""
        if v is True:
            raise ValueError(
                "Public assets are not permitted in this registry. "
                "Set is_public=False or remediate the resource before registering."
            )
        return v


class AssetCreate(AssetBase):
    pass


class AssetUpdate(BaseModel):
    """All fields optional so callers can do partial updates."""
    name: Optional[str] = Field(default=None, min_length=1, max_length=255)
    environment: Optional[Environment] = None
    owner: Optional[str] = Field(default=None, min_length=1, max_length=255)
    is_encrypted: Optional[bool] = None
    description: Optional[str] = None

    @field_validator("is_encrypted")
    @classmethod
    def must_remain_encrypted(cls, v: Optional[bool]) -> Optional[bool]:
        if v is False:
            raise ValueError("Encryption cannot be disabled on a registered asset.")
        return v


class AssetResponse(AssetBase):
    id: UUID
    created_at: datetime
    updated_at: datetime

    model_config = {"from_attributes": True}


class SecuritySummary(BaseModel):
    total: int
    encrypted: int
    unencrypted: int
    public: int  # Should always be 0; non-zero triggers an alert
    by_environment: dict
