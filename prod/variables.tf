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
