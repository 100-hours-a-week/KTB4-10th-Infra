variable "name" {
  description = "리소스 식별 이름"
  type        = string
}

variable "cluster_arn" {
  description = "Daemon을 실행할 ECS Cluster ARN"
  type        = string
}

variable "execution_role_arn" {
  description = "ECS Task Execution Role ARN (로그 전송)"
  type        = string
}

variable "node_exporter_image" {
  description = "node-exporter 이미지"
  type        = string
}

variable "node_exporter_port" {
  description = "node-exporter 포트 (호스트 네트워크)"
  type        = number
}

variable "node_exporter_memory" {
  description = "node-exporter 메모리 상한 (MiB)"
  type        = number
  default     = 64
}

variable "cadvisor_image" {
  description = "cAdvisor 이미지"
  type        = string
}

variable "cadvisor_port" {
  description = "cAdvisor 호스트 포트"
  type        = number
}

variable "cadvisor_memory" {
  description = "cAdvisor 메모리 상한 (MiB)"
  type        = number
  default     = 192
}

variable "log_retention_days" {
  description = "Daemon 로그 보존 기간 (일)"
  type        = number
  default     = 30
}
