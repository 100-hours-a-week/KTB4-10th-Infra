variable "allowed_account_ids" {
  description = "리소스 생성 허용 AWS 계정 ID 목록"
  type        = list(string)
}

variable "name" {
  description = "리소스 식별 이름"
  type        = string
  default     = "kgb-prod"
}

variable "cidr" {
  description = "VPC에서 사용할 CIDR 블록"
  type        = string
  default     = "10.0.0.0/16"
}

variable "azs" {
  description = "AZ 목록"
  type        = list(string)
  default     = ["ap-northeast-2a", "ap-northeast-2c"]
}

variable "private_app_subnets" {
  description = "Backend Private subnet CIDR"
  type        = list(string)
}

variable "private_db_subnets" {
  description = "Database Private Subnet CIDR"
  type        = list(string)
}

variable "public_subnets" {
  description = "public subnet으로 사용할 CIDR 블록 목록"
  type        = list(string)
}

variable "app_port" {
  description = "Backend 컨테이너 포트"
  type        = number
  default     = 8080
}

variable "management_port" {
  description = "Backend 관리 포트 (Actuator health, prometheus)"
  type        = number
  default     = 8081
}

variable "github_backend_subjects" {
  description = "백엔드  GitHub Actions OIDC Subject"
  type        = list(string)
}

variable "github_frontend_subjects" {
  description = "프론트엔드 GitHub Actions OIDC Subject"
  type        = list(string)
}

variable "frontend_bucket_name" {
  description = "프론트엔드 배포용  S3 버킷 이름"
  type        = string
}

variable "frontend_cloudfront_distribution_id" {
  description = "프론트엔드 배포용 CloudFront Distribution ID"
  type        = string
}

# ubuntu-resolute-26.04-amd64-server-20261003 (ap-northeast-2)
variable "nat_ami_id" {
  description = "NAT 인스턴스 AMI ID (Ubuntu 26.04, x86_64)"
  type        = string
  default     = "ami-0e677ebf2c8434c2a"
}

variable "nat_instance_type" {
  description = "NAT 인스턴스 타입 (x86_64)"
  type        = string
  default     = "t3.micro"
}

variable "db_name" {
  description = " RDS 생성 시 만들 데이터베이스 이름"
  type        = string
  default     = "kgb"
}

variable "db_master_password" {
  description = "RDS 마스터 비밀번호"
  type        = string
  sensitive   = true
  ephemeral   = true
}

variable "db_engine_version" {
  description = "RDS MySQL 엔진 버전"
  type        = string
  default     = "8.4.11"
}

variable "db_parameter_group_family" {
  description = "RDS 파라미터 그룹 패밀리"
  type        = string
  default     = "mysql8.4"
}

variable "db_instance_class" {
  description = "RDS 인스턴스 클래스"
  type        = string
  default     = "db.t3.small"
}

variable "db_allocated_storage" {
  description = "RDS 초기 스토리지 크기 (GiB)"
  type        = number
  default     = 20
}

variable "db_max_allocated_storage" {
  description = "RDS 스토리지 자동 확장 상한 (GiB)"
  type        = number
  default     = 50
}

# 02:00-03:00 KST
variable "db_backup_window" {
  description = "RDS 자동 백업 시간대 (UTC)"
  type        = string
  default     = "17:00-18:00"
}

# 월요일 03:00-04:00 KST
variable "db_maintenance_window" {
  description = "RDS 유지보수 시간대 (UTC)"
  type        = string
  default     = "sun:18:00-sun:19:00"
}

variable "ecs_instance_type" {
  description = "ECS Host 인스턴스 타입"
  type        = string
  default     = "t3.small"
}

variable "ecs_min_size" {
  description = "ECS Host 최소 인스턴스 수"
  type        = number
  default     = 2
}

variable "ecs_max_size" {
  description = "ECS Host 최대 인스턴스 수 (배포용 2대 포함)"
  type        = number
  default     = 4
}

variable "ecs_desired_capacity" {
  description = "ECS Host 초기 인스턴스 수"
  type        = number
  default     = 2
}

# V1에서 검증된 이미지로 시작, 이후 변경은 배포 파이프라인 담당 예정
variable "backend_image" {
  description = "Backend 컨테이너 이미지"
  type        = string
  default     = "ghcr.io/100-hours-a-week/ktb4-10-be:6b98f8f-20261013"
}

variable "backend_desired_count" {
  description = "실행할 Backend Task 수"
  type        = number
  default     = 2
}

variable "backend_memory" {
  # V1 실사용 약 514 MiB, 남는 메모리는 모니터링 Daemon(cAdvisor, node-exporter)용
  description = "Backend 컨테이너 메모리 상한 (MiB, t3.small 가용 1913 이내)"
  type        = number
  default     = 1536
}

variable "backend_db_username" {
  description = "Backend가 사용할 RDS 계정 이름"
  type        = string
  default     = "kgb_app"
}

variable "backend_storage_bucket_name" {
  description = "Backend 파일 저장용 S3 버킷 이름"
  type        = string
  default     = "kgb-s3-storage"
}
