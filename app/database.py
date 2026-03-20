"""
database.py
-----------
Bootstraps the SQLAlchemy engine.

In production (EKS) the pod's IAM role (via IRSA) grants access to AWS Secrets
Manager.  We read the DB_SECRET_ARN env var, fetch the secret, and build the
connection string from the returned JSON payload.

For local development set individual DB_* env vars instead and leave
DB_SECRET_ARN unset.
"""

import json
import logging
import os

import boto3
from botocore.exceptions import ClientError
from sqlalchemy import create_engine
from sqlalchemy.orm import DeclarativeBase, sessionmaker

logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Credential resolution
# ---------------------------------------------------------------------------

def _get_db_url_from_secret(secret_arn: str) -> str:
    """Fetch DB credentials from AWS Secrets Manager and return a DSN."""
    client = boto3.client("secretsmanager", region_name=os.getenv("AWS_REGION", "us-east-1"))
    try:
        response = client.get_secret_value(SecretId=secret_arn)
    except ClientError as exc:
        logger.error("Failed to retrieve secret %s: %s", secret_arn, exc)
        raise

    secret = json.loads(response["SecretString"])
    return (
        f"postgresql+psycopg2://{secret['username']}:{secret['password']}"
        f"@{secret['host']}:{secret.get('port', 5432)}/{secret['dbname']}"
    )


def _get_db_url_from_env() -> str:
    """Build a DSN from individual DB_* environment variables (local dev)."""
    return (
        f"postgresql+psycopg2://"
        f"{os.environ['DB_USER']}:{os.environ['DB_PASSWORD']}"
        f"@{os.environ['DB_HOST']}:{os.environ.get('DB_PORT', '5432')}"
        f"/{os.environ['DB_NAME']}"
    )


def get_database_url() -> str:
    secret_arn = os.getenv("DB_SECRET_ARN")
    if secret_arn:
        logger.info("Resolving DB credentials from Secrets Manager: %s", secret_arn)
        return _get_db_url_from_secret(secret_arn)
    logger.info("Resolving DB credentials from environment variables (local dev)")
    return _get_db_url_from_env()


# ---------------------------------------------------------------------------
# Engine & session
# ---------------------------------------------------------------------------

engine = create_engine(
    get_database_url(),
    pool_pre_ping=True,   # validate connections before using them
    pool_size=5,
    max_overflow=10,
)

SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)


class Base(DeclarativeBase):
    pass


# ---------------------------------------------------------------------------
# FastAPI dependency
# ---------------------------------------------------------------------------

def get_db():
    """Yield a DB session and ensure it is closed after the request."""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
