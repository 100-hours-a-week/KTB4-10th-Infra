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
}

module "iam" {
  source = "../modules/iam"
  name   = var.name

  github_backend_subjects  = var.github_backend_subjects
  github_frontend_subjects = var.github_frontend_subjects

  frontend_bucket_name                = var.frontend_bucket_name
  frontend_cloudfront_distribution_id = var.frontend_cloudfront_distribution_id

  nat_instance_ids = module.nat.instance_ids
}

module "nat" {
  source = "../modules/nat"
  name   = var.name
  azs    = var.azs

  public_subnet_ids           = module.network.public_subnet_ids
  private_app_route_table_ids = module.network.private_app_route_table_ids
  security_group_id           = module.security.nat_security_group_id

  ami_id                = var.nat_ami_id
  instance_type         = var.nat_instance_type
  instance_profile_name = module.iam.nat_instance_profile_name
}

module "rds" {
  source = "../modules/rds"
  name   = var.name

  subnet_ids        = module.network.private_db_subnet_ids
  security_group_id = module.security.rds_security_group_id

  engine_version         = var.db_engine_version
  parameter_group_family = var.db_parameter_group_family
  instance_class         = var.db_instance_class
  db_name                = var.db_name
  master_password        = var.db_master_password

  allocated_storage     = var.db_allocated_storage
  max_allocated_storage = var.db_max_allocated_storage

  backup_window      = var.db_backup_window
  maintenance_window = var.db_maintenance_window
}
