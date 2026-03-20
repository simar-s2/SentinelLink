# ── Stage 1: builder ──────────────────────────────────────────────────────────
# Install dependencies in an isolated layer so the final image stays small
# and doesn't carry pip/wheel tooling into production.
FROM python:3.12-slim AS builder

WORKDIR /build

# Install build dependencies for psycopg2
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --upgrade pip \
    && pip install --prefix=/install --no-cache-dir -r requirements.txt


# ── Stage 2: runtime ──────────────────────────────────────────────────────────
# Minimal final image — no build tools, no pip cache, no root user.
FROM python:3.12-slim AS runtime

WORKDIR /app

# Runtime-only system libraries
RUN apt-get update && apt-get install -y --no-install-recommends \
    libpq5 \
    && rm -rf /var/lib/apt/lists/*

# Copy installed packages from builder
COPY --from=builder /install /usr/local

# Copy application source
COPY . .

# Security: run as a non-root user
RUN addgroup --system sentinellink && adduser --system --ingroup sentinellink sentinellink
USER sentinellink

# Expose the application port
EXPOSE 8000

# Uvicorn with a single worker per container — horizontal scaling is handled
# by the Kubernetes HPA defined in the Helm chart.
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "1"]
