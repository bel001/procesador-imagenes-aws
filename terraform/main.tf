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

# SECURITY GROUPS (Cortafuegos virtuales)
# Security Group para las Lambdas: Solo necesitan salida por HTTPS (443)
resource "aws_security_group" "lambda_sg" {
  name        = "lambda-sg-${var.environment}"
  description = "Security Group para las Lambdas de subida y recorte"
  vpc_id      = aws_vpc.main.id

  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "sg-lambda-${var.environment}" }
}

# Security Group para el Endpoint de SQS: Solo acepta tráfico que venga de las Lambdas
resource "aws_security_group" "vpce_sqs_sg" {
  name        = "vpce-sqs-sg-${var.environment}"
  description = "Security Group para el VPC Endpoint de SQS"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.lambda_sg.id] 
    # El tráfico debe venir del SG - Security Group de arriba
  }
  tags = { Name = "sg-vpce-sqs-${var.environment}" }
}

# 9. VPC ENDPOINTS (Para que el tráfico no salga a Internet)
# S3 Gateway Endpoint: Se ancla a las tablas de enrutamiento privadas
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  
  route_table_ids = [
    aws_route_table.private_a.id,
    aws_route_table.private_b.id
  ]
  tags = { Name = "vpce-s3-${var.environment}" }
}

# SQS Interface Endpoint: Se ancla a las subredes y usa un Security Group
resource "aws_vpc_endpoint" "sqs" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.sqs"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true

  subnet_ids = [
    aws_subnet.private_a.id,
    aws_subnet.private_b.id
  ]
  
  security_group_ids = [aws_security_group.vpce_sqs_sg.id]

  tags = { Name = "vpce-sqs-${var.environment}" }
}