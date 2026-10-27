variable "name" {
  description = "리소스 식별 이름"
  type        = string
}

variable "vpc_id" {
  description = "Redis SG를 만들 VPC ID"
  type        = string
}

variable "subnet_ids" {
  description = "Redis를 둘 private subnet ID 목록"
  type        = list(string)
}

variable "client_security_group_id" {
  description = "Redis에 접속할 클라이언트 SG ID (ECS Host)"
  type        = string
}

variable "engine_version" {
  description = "Valkey 엔진 버전"
  type        = string
  default     = "8.2"
}

variable "parameter_group_name" {
  description = "파라미터 그룹 (엔진 메이저 버전과 일치)"
  type        = string
  default     = "default.valkey8"
}

variable "node_type" {
  description = "Redis 노드 타입"
  type        = string
  default     = "cache.t4g.micro"
}

variable "port" {
  description = "Redis 포트"
  type        = number
  default     = 6379
}

variable "snapshot_retention_limit" {
  description = "자동 스냅샷 보관 기간 (일, 0이면 끔)"
  type        = number
  default     = 1
}
