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
  management_port          = var.management_port
  ai_port                  = var.ai_port
  private_app_subnet_cidrs = var.private_app_subnets
}

module "iam" {
  source = "../modules/iam"
  name   = var.name

  github_backend_subjects  = var.github_backend_subjects
  github_frontend_subjects = var.github_frontend_subjects

  frontend_bucket_name                = var.frontend_bucket_name
  frontend_cloudfront_distribution_id = var.frontend_cloudfront_distribution_id

  backend_storage_bucket_name = var.backend_storage_bucket_name

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

module "ecs" {
  source = "../modules/ecs"
  name   = var.name

  subnet_ids            = module.network.private_app_subnet_ids
  security_group_id     = module.security.ecs_host_security_group_id
  instance_profile_name = module.iam.ecs_instance_profile_name

  instance_type    = var.ecs_instance_type
  min_size         = var.ecs_min_size
  max_size         = var.ecs_max_size
  desired_capacity = var.ecs_desired_capacity
}

# 컨테이너 레지스트리 인증 정보
module "registry" {
  source = "../modules/registry"
  name   = var.name
}

module "backend" {
  source = "../modules/backend"
  name   = var.name

  cluster_arn            = module.ecs.cluster_arn
  capacity_provider_name = module.ecs.capacity_provider_name
  execution_role_arn     = module.iam.task_execution_role_arn
  task_role_arn          = module.iam.task_role_arn

  ghcr_secret_arn = module.registry.ghcr_secret_arn

  image           = var.backend_image
  app_port        = var.app_port
  management_port = var.management_port
  memory          = var.backend_memory
  desired_count   = var.backend_desired_count

  # 일반 환경 변수는 backend.tf, 비밀 값은 Parameter Store
  environment = local.backend_environment

  target_group_arn = module.alb.target_group_arn
}

module "ai" {
  source = "../modules/ai"
  name   = var.name

  cluster_name = module.ecs.cluster_name
  cluster_arn  = module.ecs.cluster_arn

  subnet_id             = module.network.private_app_subnet_ids[0]
  private_ip            = var.ai_private_ip
  security_group_id     = module.security.ai_security_group_id
  instance_profile_name = module.iam.ecs_instance_profile_name

  ami_id        = var.ai_ami_id
  instance_type = var.ai_instance_type

  execution_role_arn = module.iam.task_execution_role_arn
  ghcr_secret_arn    = module.registry.ghcr_secret_arn

  image       = var.ai_image
  port        = var.ai_port
  memory      = var.ai_memory
  environment = local.ai_environment
}

module "alb" {
  source = "../modules/alb"
  name   = var.name

  vpc_id            = module.network.vpc_id
  public_subnet_ids = module.network.public_subnet_ids
  security_group_id = module.security.alb_security_group_id

  app_port        = var.app_port
  management_port = var.management_port

  domain_name               = var.domain_name
  subject_alternative_names = var.subject_alternative_names

  test_allowed_cidrs = var.alb_test_allowed_cidrs
}
