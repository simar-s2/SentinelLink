# ---------------------------------------------------------------------------
# VPC — private-only networking for the data tier.
# No public subnets, no Internet Gateway.  EKS worker nodes and RDS both
# live in private subnets; outbound traffic (for ECR pulls, Secrets Manager,
# etc.) is routed through a NAT Gateway in a minimal public subnet.
# ---------------------------------------------------------------------------

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "sentinellink-vpc" }
}

# ── Private subnets (one per AZ) ────────────────────────────────────────────
resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  # Never auto-assign public IPs — enforces zero public exposure
  map_public_ip_on_launch = false

  tags = { Name = "sentinellink-private-${count.index + 1}" }
}

# ── Minimal public subnet for NAT Gateway only ──────────────────────────────
resource "aws_subnet" "public_nat" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.100.0/28"   # /28 = 14 usable hosts — just enough for the NAT GW
  availability_zone       = var.availability_zones[0]
  map_public_ip_on_launch = false

  tags = { Name = "sentinellink-public-nat" }
}

# ── Internet Gateway (only for NAT GW) ──────────────────────────────────────
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "sentinellink-igw" }
}

# ── Elastic IP + NAT Gateway ─────────────────────────────────────────────────
resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = { Name = "sentinellink-nat-eip" }
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_nat.id
  depends_on    = [aws_internet_gateway.igw]
  tags          = { Name = "sentinellink-nat-gw" }
}

# ── Route tables ─────────────────────────────────────────────────────────────

# Public route table — only used by the NAT subnet
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "sentinellink-rt-public" }
}

resource "aws_route_table_association" "public_nat" {
  subnet_id      = aws_subnet.public_nat.id
  route_table_id = aws_route_table.public.id
}

# Private route table — all outbound via NAT; no direct internet path
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }
  tags = { Name = "sentinellink-rt-private" }
}

resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}
