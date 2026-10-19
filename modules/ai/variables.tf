variable "name" {
  description = "리소스 식별 이름"
  type        = string
}

variable "cluster_name" {
  description = "AI 서버를 등록할 ECS Cluster 이름"
  type        = string
}

variable "cluster_arn" {
  description = "AI Service를 실행할 ECS Cluster ARN"
  type        = string
}

variable "subnet_id" {
  description = "AI 서버를 둘 private-app subnet ID"
  type        = string
}

variable "private_ip" {
  description = "AI 서버 사설 IP (subnet 범위 안, 사용 중이지 않은 값)"
  type        = string
}

variable "security_group_id" {
  description = "AI host security group ID"
  type        = string
}

variable "instance_profile_name" {
  description = "ECS 등록용 instance profile 이름"
  type        = string
}

variable "ami_id" {
  description = "ECS 최적화 AMI ID (고정, 바꾸면 AI 서버가 교체됨)"
  type        = string
}

variable "instance_type" {
  description = "AI 서버 인스턴스 타입"
  type        = string
}

variable "root_volume_size" {
  description = "AI 서버 루트 볼륨 크기 (GiB, AMI 기본값 30 이상)"
  type        = number
  default     = 30
}

variable "execution_role_arn" {
  description = "ECS Task Execution Role ARN"
  type        = string
}

variable "ghcr_secret_arn" {
  description = "GHCR 인증 정보 Secrets Manager ARN"
  type        = string
}

variable "image" {
  description = "AI 컨테이너 이미지 (GHCR)"
  type        = string
}

variable "port" {
  description = "AI 서버 포트 (컨테이너, 호스트 동일)"
  type        = number
}

variable "memory" {
  description = "AI 컨테이너 메모리 상한 (MiB)"
  type        = number
}

variable "stop_timeout" {
  description = "컨테이너 종료 대기 시간 (초)"
  type        = number
  default     = 120
}

variable "desired_count" {
  description = "실행할 AI Task 수 (작업 큐가 메모리에 있어 1 유지)"
  type        = number
  default     = 1
}

variable "environment" {
  description = "AI 환경 변수"
  type        = map(string)
}

variable "secret_names" {
  description = "Parameter Store에서 주입할 AI  시크릿 환경 변수 이름"
  type        = list(string)
  default = [
    "ANTHROPIC_API_KEY",
  ]
}

variable "log_retention_days" {
  description = "AI 로그 보존 기간 (일)"
  type        = number
  default     = 90
}
