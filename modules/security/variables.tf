variable "name" {
  description = "리소스 식별 이름"
  type        = string
}

variable "vpc_id" {
  description = "보안 그룹을 만들 VPC ID"
  type        = string
}

variable "app_port" {
  description = "Backend 컨테이너 포트"
  type        = number
}

variable "management_port" {
  description = "Backend 관리 포트 (Actuator health, prometheus)"
  type        = number
}

variable "cadvisor_port" {
  description = "ECS Host의 cAdvisor 포트"
  type        = number
  default     = 8082
}

variable "private_app_subnet_cidrs" {
  description = "NAT를 사용하는 Backend Private subnet CIDR 블록 목록"
  type        = list(string)
}

variable "ai_port" {
  description = "AI 서버 포트"
  type        = number
}
