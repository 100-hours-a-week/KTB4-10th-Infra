terraform {
  required_version = "~> 1.16.0"
  required_providers {
    aws = {
      version = "~> 6.0"
      source  = "hashicorp/aws"
    }
  }

  cloud {
    organization = "KGuideBook"
    workspaces {
      name = "kgb-infra-prod"
    }
  }
}

provider "aws" {
  region              = "ap-northeast-2"
  allowed_account_ids = var.allowed_account_ids

  default_tags {
    tags = {
      Project     = "KGB-V2"
      Environment = "prod"
      ManagedBy   = "Terraform"
    }
  }
}

module "network" {
  source = "../modules/network"
  name   = var.name
  cidr   = var.cidr
  azs    = var.azs

  public_subnets      = var.public_subnets
  private_app_subnets = var.private_app_subnets
  private_db_subnets  = var.private_db_subnets
}

module "iam" {
  source = "../modules/iam"
  name   = var.name

  github_backend_subjects  = var.github_backend_subjects
  github_frontend_subjects = var.github_frontend_subjects

  frontend_bucket_name                = var.frontend_bucket_name
  frontend_cloudfront_distribution_id = var.frontend_cloudfront_distribution_id
}
