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

variable "node_exporter_port" {
  description = "node-exporter 포트"
  type        = number
}

variable "cadvisor_port" {
  description = "cAdvisor 호스트 포트"
  type        = number
}

variable "private_app_subnet_cidrs" {
  description = "NAT를 사용하는 Backend Private subnet CIDR 블록 목록"
  type        = list(string)
}

variable "ai_port" {
  description = "AI 서버 포트"
  type        = number
}

# VPC Peering 너머의 서버(예: V1 테스트 서버)에 허용할 때 사용. 비우면 규칙 없음
variable "external_db_cidrs" {
  description = "RDS 3306 접근을 허용할 VPC 밖 CIDR 목록"
  type        = list(string)
  default     = []
}

variable "external_scrape_cidrs" {
  description = "메트릭 수집(Backend 관리 포트, node-exporter, cAdvisor, AI)을 허용할 VPC 밖 CIDR 목록"
  type        = list(string)
  default     = []
}
