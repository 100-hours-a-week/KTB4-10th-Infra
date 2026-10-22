variable "name" {
  description = "리소스 식별 이름"
  type        = string
}

variable "cluster_arn" {
  description = "Backend Service를 실행할 ECS Cluster ARN"
  type        = string
}

variable "capacity_provider_name" {
  description = "Backend Task를 배치할 Capacity Provider 이름"
  type        = string
}

variable "execution_role_arn" {
  description = "ECS Task Execution Role ARN"
  type        = string
}

variable "task_role_arn" {
  description = "ECS Task Role ARN"
  type        = string
}

variable "ghcr_secret_arn" {
  description = "GHCR 인증 정보 Secrets Manager ARN (modules/registry)"
  type        = string
}

variable "image" {
  description = "Backend 컨테이너 이미지 (GHCR)"
  type        = string
}

variable "app_port" {
  description = "Backend API 포트 (컨테이너, 호스트 동일)"
  type        = number
}

variable "management_port" {
  description = "Backend 관리 포트 (Actuator health, prometheus)"
  type        = number
}

variable "memory" {
  description = "Backend 컨테이너 메모리 상한 (MiB)"
  type        = number
}

variable "desired_count" {
  description = "실행할 Backend Task 수"
  type        = number
}

variable "environment" {
  description = "Backend 일반 환경 변수"
  type        = map(string)
}

variable "secret_names" {
  description = "Parameter Store에서 주입할 Backend 비밀 환경 변수 이름"
  type        = list(string)
  default = [
    "DB_PASSWORD",
    "KAKAO_REST_API_KEY",
    "KAKAO_CLIENT_SECRET",
    "KAKAO_ADMIN_KEY",
    "COUPON_CODE",
    "TOUR_API_SERVICE_KEY",
    "WEB_PUSH_VAPID_PRIVATE_KEY",
  ]
}

variable "external_secrets" {
  description = "외부 비밀 값에서 주입할 Backend 환경 변수 (이름 => ARN)"
  type        = map(string)
  default     = {}
}

variable "log_retention_days" {
  description = "Backend 로그 보존 기간 (일)"
  type        = number
  default     = 90
}

variable "target_group_arn" {
  description = "Backend를 등록할 ALB Target Group ARN (null이면 ALB 연결 없음)"
  type        = string
  default     = null
}
