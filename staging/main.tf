terraform {
  required_version = "~> 1.16.0"
  required_providers {
    aws = {
      version = "~> 6.0"
      source  = "hashicorp/aws"
    }
  }

  # prod와 state 분리
  cloud {
    organization = "KGuideBook"
    workspaces {
      name = "kgb-infra-staging"
    }
  }
}

provider "aws" {
  region              = "ap-northeast-2"
  allowed_account_ids = var.allowed_account_ids

  default_tags {
    tags = {
      Project     = "KGB-V2"
      Environment = "staging"
      ManagedBy   = "Terraform"
    }
  }
}

# CloudFront 배포, V1 테스트 서버, VPC Peering은 콘솔에서 직접 관리 (docs/v2 staging.md)

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
  node_exporter_port       = var.node_exporter_port
  cadvisor_port            = var.cadvisor_port
  private_app_subnet_cidrs = var.private_app_subnets

  # V1 테스트 서버 (Backend가 같은 RDS 사용, 같은 서버의 Prometheus가 메트릭 수집)
  external_db_cidrs     = var.v1_test_cidrs
  external_scrape_cidrs = var.v1_test_cidrs
}

# Frontend 버킷/CloudFront는 콘솔 관리, 배포 역할만 Terraform으로 생성
module "iam" {
  source = "../modules/iam"
  name   = var.name

  github_backend_subjects  = var.github_backend_subjects
  github_ai_subjects       = var.github_ai_subjects
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

  # 계정 EIP 한도(5개) 초과. 외부에 NAT IP를 등록할 곳이 없어 자동 공인 IP로 충분
  use_eip = false
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

  # 테스트 후 지우고 다시 만드는 환경
  multi_az                = false
  deletion_protection     = false
  skip_final_snapshot     = true
  backup_retention_period = 1
}

# prod Redis(콘솔 관리)와 같은 구성
module "redis" {
  source = "../modules/redis"
  name   = var.name

  vpc_id                   = module.network.vpc_id
  subnet_ids               = module.network.private_db_subnet_ids
  client_security_group_id = module.security.ecs_host_security_group_id
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

  # Redis 인증 토큰 (modules/redis가 생성)
  external_secrets = {
    REDIS_PASSWORD = module.redis.auth_token_secret_arn
  }

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

  # LLM_MODE는 코드 수정 없이 바꾸도록 Parameter Store에서 주입
  secret_names = ["ANTHROPIC_API_KEY", "VLLM_BASE_URL", "VLLM_API_KEY", "LLM_MODE"]
}

# 모니터링 Daemon (클러스터의 모든 서버에 1개씩). 수집은 V1 테스트 서버의 Prometheus
module "exporters" {
  source = "../modules/exporters"
  name   = var.name

  cluster_arn        = module.ecs.cluster_arn
  execution_role_arn = module.iam.task_execution_role_arn

  node_exporter_image = var.node_exporter_image
  node_exporter_port  = var.node_exporter_port
  cadvisor_image      = var.cadvisor_image
  cadvisor_port       = var.cadvisor_port
}

# 운영과 같은 도메인 인증서 (Route 53의 기존 검증 레코드로 검증됨)
# CloudFront 원본은 *.kguidebook.site 레코드(예: staging-alb)로 연결
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

  deletion_protection = false
  test_allowed_cidrs  = var.alb_test_allowed_cidrs
}
