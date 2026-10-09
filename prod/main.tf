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

module "security" {
  source = "../modules/security"
  name   = var.name
  vpc_id = module.network.vpc_id

  app_port                 = var.app_port
  private_app_subnet_cidrs = var.private_app_subnets
  operator_cidrs           = var.operator_cidrs
}
