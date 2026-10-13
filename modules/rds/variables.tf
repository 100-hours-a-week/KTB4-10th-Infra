variable "name" {
  description = "리소스 식별 이름"
  type        = string
}

variable "subnet_ids" {
  description = "RDS를 둘 Database Private subnet ID 목록"
  type        = list(string)
}

variable "security_group_id" {
  description = "RDS security group ID"
  type        = string
}

variable "engine_version" {
  description = "MySQL 엔진 버전"
  type        = string
}

variable "parameter_group_family" {
  description = "파라미터 그룹 패밀리 (엔진 메이저 버전과 일치)"
  type        = string
}

variable "instance_class" {
  description = "RDS 인스턴스 클래스"
  type        = string
}

variable "allocated_storage" {
  description = "초기 스토리지 크기 (GiB)"
  type        = number
}

variable "max_allocated_storage" {
  description = "스토리지 자동 확장 상한 (GiB)"
  type        = number
}

variable "master_username" {
  description = "마스터 계정 이름"
  type        = string
  default     = "admin"
}

variable "master_password" {
  description = "마스터 계정 비밀번호"
  type        = string
  sensitive   = true
  ephemeral   = true
}

variable "db_name" {
  description = "생성 시 함께 만들 데이터베이스 이름 (null이면 만들지 않음)"
  type        = string
  default     = null
}

variable "backup_retention_period" {
  description = "자동 백업 보관 기간 (일)"
  type        = number
  default     = 7
}

variable "backup_window" {
  description = "자동 백업 시간대 (UTC)"
  type        = string
}

variable "maintenance_window" {
  description = "유지보수 시간대 (UTC, 백업 시간대와 겹치면 안 됨)"
  type        = string
}
