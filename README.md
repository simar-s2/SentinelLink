# SentinelLink

A secure infrastructure asset registry built on AWS, Kubernetes, and Terraform. SentinelLink tracks cloud resources (S3 buckets, RDS instances, EKS clusters, IAM roles, etc.) and enforces security policies — zero public exposure, mandatory encryption — at both the application and infrastructure layer.

---

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                        AWS VPC                          │
│                                                         │
│   ┌─────────────┐      ┌──────────────────────────┐    │
│   │  Private    │      │         EKS Cluster       │    │
│   │  Subnets    │      │  ┌────────────────────┐   │    │
│   │             │      │  │  sentinellink pod  │   │    │
│   │  ┌───────┐  │◄─────│  │  (FastAPI + IRSA)  │   │    │
│   │  │  RDS  │  │      │  └────────────────────┘   │    │
│   │  │  PG   │  │      │  ┌────────────────────┐   │    │
│   │  └───────┘  │      │  │  Prometheus stack  │   │    │
│   │             │      │  └────────────────────┘   │    │
│   │  ┌───────┐  │      │  ┌────────────────────┐   │    │
│   │  │  S3   │  │      │  │  Grafana dashboard │   │    │
│   │  │bucket │  │      │  └────────────────────┘   │    │
│   │  └───────┘  │      └──────────────────────────┘    │
│   └─────────────┘                                       │
│                                                         │
│   ┌──────────────────────────────────────┐              │
│   │  Secrets Manager (DB credentials)   │              │
│   └──────────────────────────────────────┘              │
└─────────────────────────────────────────────────────────┘
```

**Security controls applied:**
- S3: AES-256 SSE, public access blocked at all four levels, bucket policy denies unencrypted uploads and HTTP
- RDS: `storage_encrypted=true`, `publicly_accessible=false`, private subnets only, SG restricts port 5432 to EKS pods only
- IAM: IRSA (no long-lived credentials in pods), least-privilege policy scoped to one secret + one bucket
- App: Pydantic rejects `is_public=true` at request time; `is_encrypted=false` updates are also rejected

---

## Project Structure

```
SentinelLink/
├── app/                          # FastAPI microservice
│   ├── routes/assets.py          # CRUD + security summary endpoints
│   ├── main.py                   # App wiring, health probes, Prometheus
│   ├── database.py               # SQLAlchemy engine + Secrets Manager bootstrap
│   ├── models.py                 # Asset ORM model
│   ├── schemas.py                # Pydantic schemas with security validation
│   ├── Dockerfile                # Multi-stage, non-root runtime
│   └── requirements.txt
├── terraform/
│   ├── main.tf                   # Provider + S3 remote backend
│   ├── variables.tf
│   ├── outputs.tf
│   ├── vpc.tf                    # Private subnets, NAT gateway, no public exposure
│   ├── s3.tf                     # Encrypted bucket, access logging
│   ├── rds.tf                    # Encrypted PostgreSQL, multi-AZ in prod
│   ├── secrets.tf                # Secrets Manager for DB credentials
│   ├── iam.tf                    # IRSA role + least-privilege policy
│   └── terraform.tfvars.example
├── helm/sentinellink/
│   ├── Chart.yaml
│   ├── values.yaml
│   └── templates/
│       ├── deployment.yaml       # Topology spread, security contexts
│       ├── service.yaml
│       ├── serviceaccount.yaml   # IRSA annotation
│       ├── configmap.yaml
│       └── hpa.yaml              # CPU + memory autoscaling
├── k8s/monitoring/
│   ├── prometheus-values.yaml    # Scrape config + alerting rules
│   └── grafana-values.yaml       # Auto-provisioned datasource + dashboard
└── .github/workflows/
    ├── ci.yml                    # PR: lint + test + docker build
    └── deploy.yml                # Main: ECR push → tf apply → helm upgrade
```

---

## Prerequisites

| Tool        | Version   |
|-------------|-----------|
| Terraform   | >= 1.7    |
| kubectl     | >= 1.29   |
| Helm        | >= 3.14   |
| Docker      | >= 24     |
| AWS CLI     | >= 2.15   |
| Python      | >= 3.12   |

---

## Quick Start (Local Development)

```bash
# 1. Start a local Postgres instance
docker run -d \
  --name sentinellink-db \
  -e POSTGRES_USER=sentinellink_admin \
  -e POSTGRES_PASSWORD=localpassword \
  -e POSTGRES_DB=sentinellink \
  -p 5432:5432 \
  postgres:16

# 2. Install Python dependencies
cd app
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt

# 3. Set environment variables (no Secrets Manager locally)
export DB_USER=sentinellink_admin
export DB_PASSWORD=localpassword
export DB_HOST=localhost
export DB_PORT=5432
export DB_NAME=sentinellink

# 4. Run the API
uvicorn main:app --reload --port 8000

# 5. Open the interactive docs
open http://localhost:8000/docs
```

---

## Terraform Deployment

```bash
cd terraform

# Copy and fill in the example vars file (never commit terraform.tfvars)
cp terraform.tfvars.example terraform.tfvars

# Initialise (connects to S3 backend)
terraform init

# Review the plan
terraform plan

# Apply
terraform apply
```

---

## Kubernetes Deployment

```bash
# Update kubeconfig
aws eks update-kubeconfig --region us-east-1 --name sentinellink-cluster

# Create namespace
kubectl create namespace sentinellink

# Deploy via Helm
helm upgrade --install sentinellink ./helm/sentinellink \
  --namespace sentinellink \
  --set image.tag=<IMAGE_TAG> \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=<IRSA_ROLE_ARN> \
  --set env.DB_SECRET_ARN=<SECRET_ARN>
```

---

## Monitoring

```bash
# Install Prometheus stack
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install prometheus prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace \
  -f k8s/monitoring/prometheus-values.yaml

# Install Grafana
helm repo add grafana https://grafana.github.io/helm-charts
helm install grafana grafana/grafana \
  -n monitoring \
  -f k8s/monitoring/grafana-values.yaml

# Port-forward Grafana locally
kubectl port-forward svc/grafana 3000:80 -n monitoring
open http://localhost:3000  # admin / changeme-use-a-secret-in-production
```

The **SentinelLink — Asset Security Overview** dashboard is auto-provisioned and shows:
- Total / encrypted / public asset counts (public must always be 0)
- HTTP request rate and 5xx error rate
- Asset distribution by environment

Prometheus alert rules fire on: public asset detection, API downtime, and high error rate.

---

## API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/v1/assets` | List all assets (supports `?environment=` and `?asset_type=` filters) |
| `POST` | `/api/v1/assets` | Register a new asset |
| `GET` | `/api/v1/assets/summary` | Security posture summary |
| `GET` | `/api/v1/assets/{id}` | Get a single asset |
| `PUT` | `/api/v1/assets/{id}` | Partial update |
| `DELETE` | `/api/v1/assets/{id}` | Deregister an asset |
| `GET` | `/healthz` | Kubernetes liveness probe |
| `GET` | `/readyz` | Kubernetes readiness probe |
| `GET` | `/metrics` | Prometheus metrics |
| `GET` | `/docs` | Swagger UI |
