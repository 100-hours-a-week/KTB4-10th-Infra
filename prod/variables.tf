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

variable "ai_port" {
  description = "AI 서버 포트"
  type        = number
  default     = 8000
}

variable "node_exporter_port" {
  description = "node-exporter 포트"
  type        = number
  default     = 9100
}

# Backend 8080, 8081과 겹치지 않게 지정
variable "cadvisor_port" {
  description = "cAdvisor 호스트 포트"
  type        = number
  default     = 8082
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
  default     = "kgb"
}

variable "backend_storage_bucket_name" {
  description = "Backend 파일 저장용 S3 버킷 이름"
  type        = string
  default     = "kgb-s3-storage"
}

variable "domain_name" {
  description = "서비스 도메인 (ALB 인증서 기본 도메인)"
  type        = string
  default     = "kguidebook.site"
}

variable "subject_alternative_names" {
  description = "ALB 인증서 추가 도메인"
  type        = list(string)
  default     = ["*.kguidebook.site"]
}

# CloudFront 연결 전 직접 확인할 때만 내 IP를 넣고, 테스트 후 비울 것
variable "alb_test_allowed_cidrs" {
  description = "테스트용 ALB 443 접근 허용 CIDR (예: [\"1.2.3.4/32\"])"
  type        = list(string)
  default     = []
}

# ---------- AI ----------

variable "ai_image" {
  description = "AI 컨테이너 이미지"
  type        = string
  default     = "ghcr.io/100-hours-a-week/ktb4-10-ai:ff49476-20261015"
}

# al2023-ami-ecs-hvm-2023.0.20261014-kernel-6.1-x86_64 (ap-northeast-2)
# aws_instance는 AMI가 바뀌면 교체되므로 자동 조회하지 않고 고정
variable "ai_ami_id" {
  description = "AI 서버 AMI ID (ECS 최적화 Amazon Linux 2023, x86_64)"
  type        = string
  default     = "ami-08afa937d0ef1a748"
}

variable "ai_instance_type" {
  description = "AI 서버 인스턴스 타입"
  type        = string
  default     = "t3.small"
}

# private-app-a(10.10.10.0/24) 뒤쪽 주소. ASG 서버와 겹치지 않게 사용 중인지 확인 후 지정
variable "ai_private_ip" {
  description = "AI 서버 사설 IP"
  type        = string
  default     = "10.10.10.250"
}

variable "ai_memory" {
  description = "AI 컨테이너 메모리 상한 (MiB, V1 실측 최대 약 135 MiB)"
  type        = number
  default     = 1024
}

# ---------- Monitoring Daemon ----------

# V1 kgb-monitoring과 같은 버전 (대시보드 호환)
variable "node_exporter_image" {
  description = "node-exporter 이미지"
  type        = string
  default     = "quay.io/prometheus/node-exporter:v1.12.1"
}

variable "cadvisor_image" {
  description = "cAdvisor 이미지"
  type        = string
  default     = "ghcr.io/google/cadvisor:v0.60.6"
}
