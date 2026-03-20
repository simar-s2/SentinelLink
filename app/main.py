"""
main.py
-------
SentinelLink — Secure Asset Registry
Entry point for the FastAPI application.

Responsibilities:
  - Wire up the database (create tables on first run)
  - Register all routers
  - Expose /healthz for Kubernetes liveness/readiness probes
  - Expose /metrics for Prometheus scraping (via prometheus-fastapi-instrumentator)
"""

import logging
import os

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from prometheus_fastapi_instrumentator import Instrumentator

from database import Base, engine
from routes.assets import router as assets_router

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s — %(message)s",
)
logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# App init
# ---------------------------------------------------------------------------
app = FastAPI(
    title="SentinelLink",
    description=(
        "Secure asset registry for cloud infrastructure. "
        "Tracks S3, RDS, EC2, EKS, IAM, and other AWS resources "
        "with enforced encryption and zero-public-exposure policies."
    ),
    version="1.0.0",
    docs_url="/docs",
    redoc_url="/redoc",
)

# ---------------------------------------------------------------------------
# CORS — tighten allowed_origins in production via environment variable
# ---------------------------------------------------------------------------
allowed_origins = os.getenv("ALLOWED_ORIGINS", "http://localhost:3000").split(",")
app.add_middleware(
    CORSMiddleware,
    allow_origins=allowed_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ---------------------------------------------------------------------------
# Prometheus metrics — exposes /metrics endpoint automatically
# ---------------------------------------------------------------------------
Instrumentator().instrument(app).expose(app)

# ---------------------------------------------------------------------------
# Routers
# ---------------------------------------------------------------------------
app.include_router(assets_router, prefix="/api/v1")

# ---------------------------------------------------------------------------
# Startup: create tables if they don't exist yet
# In production this is handled by Alembic migrations in CI/CD.
# This fallback is intentional for local development only.
# ---------------------------------------------------------------------------
@app.on_event("startup")
async def on_startup():
    logger.info("Running database table creation (dev fallback)...")
    Base.metadata.create_all(bind=engine)
    logger.info("SentinelLink started successfully.")


# ---------------------------------------------------------------------------
# Health probes
# ---------------------------------------------------------------------------
@app.get("/healthz", tags=["ops"], summary="Liveness probe")
def healthz():
    """Returns 200 OK. Used by Kubernetes liveness probe."""
    return {"status": "ok"}


@app.get("/readyz", tags=["ops"], summary="Readiness probe")
def readyz():
    """
    Returns 200 OK when the app is ready to serve traffic.
    Could be extended to check DB connectivity.
    """
    return {"status": "ready"}
