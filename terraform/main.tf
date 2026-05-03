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
  cidr_block              = cidrsubnet(aws_vpc.main.cidr_block, 8, 1)
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = { Name = "public-subnet-a-${var.environment}" }
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(aws_vpc.main.cidr_block, 8, 2)
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true

  tags = { Name = "public-subnet-b-${var.environment}" }
}


# SUBNETS PRIVADAS (Texto fijo)
resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(aws_vpc.main.cidr_block, 8, 11)
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = { Name = "private-subnet-a-${var.environment}" }
}

resource "aws_subnet" "private_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(aws_vpc.main.cidr_block, 8, 12)
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
# Security Groups separados para Lambdas con salida restringida (Outbound: TCP 443)
resource "aws_security_group" "upload_lambda_sg" {
  name        = "upload-lambda-sg-${var.environment}"
  description = "Security group para Upload Lambda"
  vpc_id      = aws_vpc.main.id

  egress {
    description     = "Permitir trafico HTTPS solo hacia S3 y SQS Endpoints"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    prefix_list_ids = [aws_vpc_endpoint.s3.prefix_list_id]
    security_groups = [aws_security_group.vpce_sqs_sg.id] 
  }
  tags = { Name = "sg-upload-lambda-${var.environment}" }
}

resource "aws_security_group" "crop_lambda_sg" {
  name        = "crop-lambda-sg-${var.environment}"
  description = "Security group para Crop Lambda"
  vpc_id      = aws_vpc.main.id

  egress {
    description     = "Permitir trafico HTTPS solo hacia S3 y SQS Endpoints"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    prefix_list_ids = [aws_vpc_endpoint.s3.prefix_list_id]
    security_groups = [aws_security_group.vpce_sqs_sg.id]
  }
  tags = { Name = "sg-crop-lambda-${var.environment}" }
}

# Security Group para el Endpoint de SQS: Solo acepta tráfico que venga de las Lambdas
resource "aws_security_group" "vpce_sqs_sg" {
  name        = "vpce-sqs-sg-${var.environment}"
  description = "Security Group para el VPC Endpoint de SQS"
  vpc_id      = aws_vpc.main.id
  tags = { Name = "sg-vpce-sqs-${var.environment}" }
}

resource "aws_security_group_rule" "vpce_sqs_ingress_upload" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.vpce_sqs_sg.id
  source_security_group_id = aws_security_group.upload_lambda_sg.id
}

resource "aws_security_group_rule" "vpce_sqs_ingress_crop" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.vpce_sqs_sg.id
  source_security_group_id = aws_security_group.crop_lambda_sg.id
}

# VPC ENDPOINTS (Para que el tráfico no salga a Internet)
# S3 Gateway Endpoint: Se ancla a las tablas de enrutamiento privadas
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  
  route_table_ids = [
    aws_route_table.private_a.id,
    aws_route_table.private_b.id
  ]
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = "*"
        Action    = [
          "s3:GetObject",
          "s3:PutObject"
        ]
        Resource  = "${aws_s3_bucket.images.arn}/*"
      }
    ]
  })

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
# ALMACENAMIENTO DE IMÁGENES (Amazon S3)
# Sufijo aleatorio (algo aletaorio creo que es por le nombre)
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Creación del Bucket
resource "aws_s3_bucket" "images" {
  bucket = "image-processor-${var.environment}-images-${random_string.suffix.result}"
  tags   = { Name = "bucket-images-${var.environment}" }
}

# Bloqueo de Acceso Público 
resource "aws_s3_bucket_public_access_block" "images_access" {
  bucket                  = aws_s3_bucket.images.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Versionado 
resource "aws_s3_bucket_versioning" "images_versioning" {
  bucket = aws_s3_bucket.images.id
  versioning_configuration { status = "Enabled" }
}

# Encriptación en reposo
resource "aws_s3_bucket_server_side_encryption_configuration" "images_encryption" {
  bucket = aws_s3_bucket.images.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Reglas de Ciclo de Vida
resource "aws_s3_bucket_lifecycle_configuration" "images_lifecycle" {
  bucket = aws_s3_bucket.images.id

  # Las imágenes originales se borran al mes
  rule {
    id     = "expire-uploads-30-days"
    status = "Enabled"
    filter { prefix = "uploads/" }
    expiration { days = 30 }
  }

  # Las imágenes procesadas se borran a los 3 meses
  rule {
    id     = "expire-processed-90-days"
    status = "Enabled"
    filter { prefix = "processed/" }
    expiration { days = 90 }
  }
}
# SISTEMA DE MENSAJERÍA Y TOLERANCIA A FALLOS (Amazon SQS)

# Dead-Letter Queue (DLQ)
# Retención de 14 días (1209600 segundos)
resource "aws_sqs_queue" "image_dlq" {
  name                      = "image-processor-${var.environment}-image-dlq"
  message_retention_seconds = 1209600 
  tags                      = { Name = "sqs-dlq-${var.environment}" }
}

# Cola Principal (Main Queue)
resource "aws_sqs_queue" "image_queue" {
  name                       = "image-processor-${var.environment}-image-queue"
  visibility_timeout_seconds = 360   # 6x Lambda timeout
  message_retention_seconds  = 86400 # 1 día
  receive_wait_time_seconds  = 20    # Si no llega en 20 segunds seria ocmo pregunta ya llego? y el correo me responde no y asi 

  # Redrive Policy: Si falla 3 veces, se va al DLQ
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.image_dlq.arn
    maxReceiveCount     = 3
  })

  tags = { Name = "sqs-main-${var.environment}" }
}

# Permiso IAM para que S3 le escriba a la Cola Principal
resource "aws_sqs_queue_policy" "allow_s3" {
  queue_url = aws_sqs_queue.image_queue.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "s3.amazonaws.com" }
        Action    = "sqs:SendMessage"
        Resource  = aws_sqs_queue.image_queue.arn
        Condition = { ArnEquals = { "aws:SourceArn" : aws_s3_bucket.images.arn } }
      }
    ]
  })
}

# Evento: S3 le avisa a SQS cuando llega una imagen nueva a "upload"
resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.images.id
  queue {
    queue_arn     = aws_sqs_queue.image_queue.arn
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = "uploads/"
  }
  depends_on = [aws_sqs_queue_policy.allow_s3] # Aseguramos que el permiso exista primero
}
# IAM: LEAST-PRIVILEGE ROLES (Seguridad)
# Política base para permitir que las Lambdas asuman un rol
data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

# Rol para Upload-Lambda
resource "aws_iam_role" "upload_role" {
  name               = "upload-lambda-role-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

# Permisos básicos de ejecución y acceso a la VPC
resource "aws_iam_role_policy_attachment" "upload_basic_exec" {
  role       = aws_iam_role.upload_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
resource "aws_iam_role_policy_attachment" "upload_vpc_access" {
  role       = aws_iam_role.upload_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# Permiso estricto: Solo puede ESCRIBIR en la carpeta "upload"
resource "aws_iam_role_policy" "upload_s3_policy" {
  name = "upload-s3-policy"
  role = aws_iam_role.upload_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:PutObject"]
      Resource = "${aws_s3_bucket.images.arn}/uploads/*"
    }]
  })
}

# Rol para Crop-Lambda
resource "aws_iam_role" "crop_role" {
  name               = "crop-lambda-role-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy_attachment" "crop_basic_exec" {
  role       = aws_iam_role.crop_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
resource "aws_iam_role_policy_attachment" "crop_vpc_access" {
  role       = aws_iam_role.crop_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# Permisos estrictos: Leer de "uploads/", Escribir en "processed/" y manejar la cola SQS
resource "aws_iam_role_policy" "crop_custom_policy" {
  name = "crop-custom-policy"
  role = aws_iam_role.crop_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow",
        Action   = ["s3:GetObject"],
        Resource = "${aws_s3_bucket.images.arn}/uploads/*"
      },
      {
        Effect   = "Allow",
        Action   = ["s3:PutObject"],
        Resource = "${aws_s3_bucket.images.arn}/processed/*"
      },
      {
        Effect   = "Allow",
        Action   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes", "sqs:ChangeMessageVisibility"],
        Resource = aws_sqs_queue.image_queue.arn
      }
    ]
  })
}

# CÓMPUTO: AWS LAMBDAS
# Upload Lambda
resource "aws_lambda_function" "upload_lambda" {
  filename      = "upload-lambda.zip" # Archivo dummy, luego subiremos el código real
  function_name = "upload-lambda-${var.environment}"
  role          = aws_iam_role.upload_role.arn
  handler       = "index.handler"
  runtime       = "nodejs20.x"
  memory_size   = 256
  timeout       = 30

  # Se distribuye en las subredes privadas con su Security Group
  vpc_config {
    subnet_ids         = [aws_subnet.private_a.id, aws_subnet.private_b.id]
    security_group_ids = [aws_security_group.upload_lambda_sg.id] 
  }
  environment {
    variables = {
      S3_BUCKET     = aws_s3_bucket.images.id
      UPLOAD_PREFIX = "uploads/"
    }
  }
}

# Crop Lambda
resource "aws_lambda_function" "crop_lambda" {
  filename      = "crop-lambda.zip" # Archivo de prueba, luego subir el código real
  function_name = "crop-lambda-${var.environment}"
  role          = aws_iam_role.crop_role.arn
  handler       = "index.handler"
  runtime       = "nodejs20.x"
  memory_size   = 512
  timeout       = 60

  vpc_config {
    subnet_ids         = [aws_subnet.private_a.id, aws_subnet.private_b.id]
    security_group_ids = [aws_security_group.crop_lambda_sg.id]
  }
  environment {
    variables = {
      S3_BUCKET        = aws_s3_bucket.images.id
      PROCESSED_PREFIX = "processed/"
    }
  }
}

# Conexión SQS -> Lambda (ESM trigger, batch size 5)
resource "aws_lambda_event_source_mapping" "sqs_trigger" {
  event_source_arn        = aws_sqs_queue.image_queue.arn
  function_name           = aws_lambda_function.crop_lambda.arn
  batch_size              = 5
  function_response_types = ["ReportBatchItemFailures"]
}
# API GATEWAY HTTP API 

# Crear la API
resource "aws_apigatewayv2_api" "http_api" {
  name          = "image-api-${var.environment}"
  protocol_type = "HTTP"

  # Configuración CORS exigida en el diagrama
  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["POST"]
    allow_headers = ["Content-Type"]
  }
}

# Crear la Ruta
resource "aws_apigatewayv2_route" "upload_route" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "POST /upload"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

# Integrar la Ruta con la Lambda de Subida
resource "aws_apigatewayv2_integration" "lambda_integration" {
  api_id                 = aws_apigatewayv2_api.http_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.upload_lambda.invoke_arn
  payload_format_version = "2.0" 
}

# Dar permiso al API Gateway para ejecutar la Lambda
resource "aws_lambda_permission" "api_gw_invoke" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.upload_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http_api.execution_arn}/*/*"
}

# Crear el Stage de Despliegue con límites de seguridad (Throttling)
resource "aws_apigatewayv2_stage" "default_stage" {
  api_id      = aws_apigatewayv2_api.http_api.id
  name        = "$default"
  auto_deploy = true

  # Throttling: Límite de 10,000 peticiones por segundo (según diagrama)
  default_route_settings {
    throttling_burst_limit = 10000
    throttling_rate_limit  = 10000
  }

  # Configuración de Logs (Bitácora de accesos)
  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gw_logs.arn
    format          = "{ \"requestId\":\"$context.requestId\", \"ip\": \"$context.identity.sourceIp\", \"requestTime\":\"$context.requestTime\", \"httpMethod\":\"$context.httpMethod\",\"routeKey\":\"$context.routeKey\", \"status\":\"$context.status\",\"protocol\":\"$context.protocol\", \"responseLength\":\"$context.responseLength\" }"
  }
}

# OBSERVABILITY (CloudWatch Logs & Alarms)
# Log Groups para guardar la actividad de las Lambdas y el API Gateway
# Retención de 14 días para ahorrar costos
resource "aws_cloudwatch_log_group" "upload_logs" {
  name              = "/aws/lambda/${aws_lambda_function.upload_lambda.function_name}"
  retention_in_days = 14
}

resource "aws_cloudwatch_log_group" "crop_logs" {
  name              = "/aws/lambda/${aws_lambda_function.crop_lambda.function_name}"
  retention_in_days = 14
}

resource "aws_cloudwatch_log_group" "api_gw_logs" {
  name              = "/aws/apigateway/image-api-${var.environment}"
  retention_in_days = 14
}

# Sistema de Alerta para la Dead Letter Queue (DLQ)
# Canal de notificaciones (Tema SNS)
resource "aws_sns_topic" "dlq_alerts" {
  name = "dlq-alerts-topic-${var.environment}"
}

# Alarma: Si llega aunque sea 1 mensaje de error a la DLQ, dispara una alerta
resource "aws_cloudwatch_metric_alarm" "dlq_alarm" {
  alarm_name          = "dlq-messages-alarm-${var.environment}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Alarma que se dispara si hay mensajes defectuosos en la DLQ"
  alarm_actions       = [aws_sns_topic.dlq_alerts.arn]
  
  dimensions = {
    QueueName = aws_sqs_queue.image_dlq.name
  }
}
