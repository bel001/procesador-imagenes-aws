# DATOS DE AWS (Zonas de Disponibilidad)
data "aws_availability_zones" "available" {
  state = "available"
}


# VPC (La red principal)
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr # Esto jala el 10.0.0.0/16 de variables
  enable_dns_support   = true 
  enable_dns_hostnames = true

  tags = {
    Name = "vpc-${var.environment}"
  }
}


# SUBNETS PÚBLICAS (Texto fijo)
resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = { Name = "public-subnet-a-${var.environment}" }
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true

  tags = { Name = "public-subnet-b-${var.environment}" }
}


# SUBNETS PRIVADAS (Texto fijo)
resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.11.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = { Name = "private-subnet-a-${var.environment}" }
}

resource "aws_subnet" "private_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.12.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = { Name = "private-subnet-b-${var.environment}" }
}

# SALIDA A INTERNET (IGW y 2 NAT Gateways)
# Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "igw-${var.environment}" }
}

# NAT Gateway A (En subred pública A)
resource "aws_eip" "nat_a" {
  domain = "vpc"
  tags   = { Name = "eip-nat-a-${var.environment}" }
}

resource "aws_nat_gateway" "nat_a" {
  allocation_id = aws_eip.nat_a.id
  subnet_id     = aws_subnet.public_a.id
  depends_on    = [aws_internet_gateway.igw]
  tags          = { Name = "nat-gw-a-${var.environment}" }
}

# NAT Gateway B (En subred pública B - High Availability)
resource "aws_eip" "nat_b" {
  domain = "vpc"
  tags   = { Name = "eip-nat-b-${var.environment}" }
}

resource "aws_nat_gateway" "nat_b" {
  allocation_id = aws_eip.nat_b.id
  subnet_id     = aws_subnet.public_b.id
  depends_on    = [aws_internet_gateway.igw]
  tags          = { Name = "nat-gw-b-${var.environment}" }
}

# TABLAS DE ENRUTAMIENTO
# Tabla Pública
# Todo lo que va a internet sale por el IGW
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "rt-public-${var.environment}" }
}

# Tabla Privada A: Todo lo que va a internet sale por NAT A
resource "aws_route_table" "private_a" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_a.id
  }
  tags = { Name = "rt-private-a-${var.environment}" }
}

# Tabla Privada B Todo lo que va a internet sale por NAT B
resource "aws_route_table" "private_b" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_b.id
  }
  tags = { Name = "rt-private-b-${var.environment}" }
}

# ASOCIACIONES DE TABLAS A SUBREDES
resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}
resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}
resource "aws_route_table_association" "private_a" {
  subnet_id      = aws_subnet.private_a.id
  route_table_id = aws_route_table.private_a.id
}
resource "aws_route_table_association" "private_b" {
  subnet_id      = aws_subnet.private_b.id
  route_table_id = aws_route_table.private_b.id
}