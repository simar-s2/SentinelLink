"""
routes/assets.py
----------------
CRUD endpoints for the asset registry.

GET    /assets              - list all assets (supports ?environment= and ?asset_type= filters)
POST   /assets              - register a new asset
GET    /assets/summary      - security posture summary (used by Grafana)
GET    /assets/{asset_id}   - get a single asset
PUT    /assets/{asset_id}   - partial update
DELETE /assets/{asset_id}   - deregister an asset
"""

from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.orm import Session

from database import get_db
from models import Asset, AssetType, Environment
from schemas import AssetCreate, AssetResponse, AssetUpdate, SecuritySummary

router = APIRouter(prefix="/assets", tags=["assets"])


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _get_or_404(asset_id: UUID, db: Session) -> Asset:
    asset = db.query(Asset).filter(Asset.id == asset_id).first()
    if not asset:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Asset not found")
    return asset


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------

@router.get("", response_model=list[AssetResponse])
def list_assets(
    environment: Environment | None = Query(default=None),
    asset_type: AssetType | None = Query(default=None),
    owner: str | None = Query(default=None),
    db: Session = Depends(get_db),
):
    """Return all registered assets, optionally filtered."""
    q = db.query(Asset)
    if environment:
        q = q.filter(Asset.environment == environment)
    if asset_type:
        q = q.filter(Asset.asset_type == asset_type)
    if owner:
        q = q.filter(Asset.owner == owner)
    return q.order_by(Asset.created_at.desc()).all()


@router.post("", response_model=AssetResponse, status_code=status.HTTP_201_CREATED)
def create_asset(payload: AssetCreate, db: Session = Depends(get_db)):
    """Register a new infrastructure asset."""
    # Reject duplicates by ARN
    if payload.arn:
        existing = db.query(Asset).filter(Asset.arn == payload.arn).first()
        if existing:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail=f"Asset with ARN {payload.arn} is already registered (id={existing.id}).",
            )

    asset = Asset(**payload.model_dump())
    db.add(asset)
    db.commit()
    db.refresh(asset)
    return asset


@router.get("/summary", response_model=SecuritySummary)
def security_summary(db: Session = Depends(get_db)):
    """
    Aggregate security posture metrics.
    This endpoint is scraped by Prometheus via the /metrics path and also
    consumed directly by the Grafana dashboard.
    """
    all_assets = db.query(Asset).all()
    total = len(all_assets)
    encrypted = sum(1 for a in all_assets if a.is_encrypted)
    public = sum(1 for a in all_assets if a.is_public)

    by_env: dict[str, int] = {}
    for asset in all_assets:
        by_env[asset.environment.value] = by_env.get(asset.environment.value, 0) + 1

    return SecuritySummary(
        total=total,
        encrypted=encrypted,
        unencrypted=total - encrypted,
        public=public,
        by_environment=by_env,
    )


@router.get("/{asset_id}", response_model=AssetResponse)
def get_asset(asset_id: UUID, db: Session = Depends(get_db)):
    return _get_or_404(asset_id, db)


@router.put("/{asset_id}", response_model=AssetResponse)
def update_asset(asset_id: UUID, payload: AssetUpdate, db: Session = Depends(get_db)):
    asset = _get_or_404(asset_id, db)
    update_data = payload.model_dump(exclude_unset=True)
    for field, value in update_data.items():
        setattr(asset, field, value)
    db.commit()
    db.refresh(asset)
    return asset


@router.delete("/{asset_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_asset(asset_id: UUID, db: Session = Depends(get_db)):
    asset = _get_or_404(asset_id, db)
    db.delete(asset)
    db.commit()
