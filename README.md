# Proyecto: Procesador de Imágenes en AWS con Terraform

Este es el entregable de mi proyecto donde implemento una arquitectura Serverless en AWS para subir y procesar imágenes de forma automática. Toda la infraestructura fue automatizada usando Terraform.

## Arquitectura

Para cumplir con el diagrama de la rúbrica, construí los siguientes componentes:
- **Redes (VPC):** Una VPC con subredes públicas y privadas. Para evitar conflictos de IPs entre los entornos (dev, qa, prod), usé la función `cidrsubnet()` de Terraform.
- **API Gateway:** Funciona como el endpoint principal para recibir las imágenes desde afuera.
- **Lambdas (Node.js):**
  - `upload_lambda`: Recibe la imagen desde el API Gateway y la guarda en un bucket de S3 de entrada.
  - `crop_lambda`: Se activa por eventos de S3, recorta la imagen usando `sharp` y la guarda en el bucket de salida.
- **Amazon S3:** Dos buckets para almacenar las imágenes originales y las ya procesadas.
- **Notificaciones y Colas:** Usé SQS y SNS para desacoplar el proceso y manejar los eventos.
- **CloudWatch:** Para guardar los logs de las funciones y configurar las alarmas.

## Requisitos para probarlo

Para poder levantar la infraestructura en tu propia cuenta necesitas:
- Tener una cuenta de AWS activa.
- Tener instalado y configurado AWS CLI (`aws configure`).
- Tener instalado Terraform.
- Tener Node.js v20 (el código de las lambdas lo requiere).

## Pasos para desplegar

El código está preparado para funcionar en diferentes entornos usando Workspaces de Terraform y archivos `.tfvars`.

1. Clona el repositorio y entra a la carpeta de Terraform:
   ```bash
   git clone https://github.com/bel001/procesador-imagenes-aws.git
   cd procesador-imagenes-aws/terraform
   ```

2. Inicializa el proyecto para descargar los providers:
   ```bash
   terraform init
   ```

3. Crea o selecciona el entorno y despliega (repetir según el entorno que se quiera levantar):

   **Para Desarrollo (DEV):**
   ```bash
   terraform workspace select dev || terraform workspace new dev
   terraform apply -var-file="dev.tfvars" -auto-approve
   ```

   **Para Pruebas (QA):**
   ```bash
   terraform workspace select qa || terraform workspace new qa
   terraform apply -var-file="qa.tfvars" -auto-approve
   ```

   **Para Producción (PROD):**
   ```bash
   terraform workspace select prod || terraform workspace new prod
   terraform apply -var-file="prod.tfvars" -auto-approve
   ```

## Evidencia de destrucción de recursos

Tal como se solicita, para evitar generar costos extras, se deben apagar todos los servicios al terminar las pruebas. Configuré los buckets con `force_destroy = true` para que Terraform pueda borrarlos sin importar si hay imágenes adentro.

Los comandos que utilicé para limpiar la cuenta en los 3 entornos fueron:

```bash
# Destruir DEV
terraform workspace select dev
terraform destroy -var-file="dev.tfvars" -auto-approve

# Destruir QA
terraform workspace select qa
terraform destroy -var-file="qa.tfvars" -auto-approve

# Destruir PROD
terraform workspace select prod
terraform destroy -var-file="prod.tfvars" -auto-approve
```

### Salida de la consola (Evidencia)

A continuación muestro la salida final de la consola después de ejecutar el destroy, comprobando que se eliminaron los 55 recursos creados en el entorno de producción:

```text
aws_subnet.private_a: Destruction complete after 21m28s
aws_subnet.private_b: Destruction complete after 21m29s
aws_security_group.upload_lambda_sg: Destruction complete after 23m30s
aws_vpc_endpoint.s3: Destroying... [id=vpce-0ba2a844864b68410]
aws_security_group.vpce_sqs_sg: Destroying... [id=sg-00c6ec5732e17f909]
aws_security_group.vpce_sqs_sg: Destruction complete after 1s
aws_vpc_endpoint.s3: Destruction complete after 6s
aws_route_table.private_a: Destroying... [id=rtb-0536e18cefcf10655]
aws_route_table.private_b: Destroying... [id=rtb-0ff96b139d664b310]
aws_s3_bucket.images: Destroying... [id=image-processor-prod-images-vmp8a9]
aws_s3_bucket.images: Destruction complete after 0s
random_string.suffix: Destroying... [id=vmp8a9]
random_string.suffix: Destruction complete after 0s
aws_route_table.private_a: Destruction complete after 1s
aws_nat_gateway.nat_a: Destroying... [id=nat-011ce939a4bb28516]
aws_route_table.private_b: Destruction complete after 1s
aws_nat_gateway.nat_b: Destroying... [id=nat-03f9e63c99f864f4d]
aws_nat_gateway.nat_a: Destruction complete after 1m2s
aws_eip.nat_a: Destroying... [id=eipalloc-095347f99c9d0f231]
aws_subnet.public_a: Destroying... [id=subnet-0a419f239b1b3ab66]
aws_subnet.public_a: Destruction complete after 0s
aws_eip.nat_a: Destruction complete after 1s
aws_nat_gateway.nat_b: Destruction complete after 1m12s
aws_internet_gateway.igw: Destroying... [id=igw-071be6416b5c665a9]
aws_subnet.public_b: Destroying... [id=subnet-00c791b180ae6c536]
aws_eip.nat_b: Destroying... [id=eipalloc-0bb8c8a378e59dc01]
aws_internet_gateway.igw: Destruction complete after 1s
aws_subnet.public_b: Destruction complete after 1s
aws_vpc.main: Destroying... [id=vpc-063f4c726dde58a0e]
aws_eip.nat_b: Destruction complete after 1s
aws_vpc.main: Destruction complete after 1s

Destroy complete! Resources: 55 destroyed.
```