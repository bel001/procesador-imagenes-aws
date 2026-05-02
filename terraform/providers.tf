terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  # Estas etiquetas se aplicarán a TODOS los recursos que creen en
  default_tags {
    tags = {
      Project     = "ProcesadorImagenes"
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}