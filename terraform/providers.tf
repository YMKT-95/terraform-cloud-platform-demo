terraform {
  required_version = ">= 1.16.5, < 1.17.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "terraform-cloud-platform-demo"
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}
