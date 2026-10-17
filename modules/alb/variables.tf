variable "name" {
  description = "리소스 식별 이름"
  type        = string
}

variable "vpc_id" {
  description = "Target Group을 만들 VPC ID"
  type        = string
}

variable "public_subnet_ids" {
  description = "ALB를 둘 public subnet ID 목록"
  type        = list(string)
}

variable "security_group_id" {
  description = "ALB security group ID"
  type        = string
}

variable "app_port" {
  description = "Backend API 포트 (트래픽 전달)"
  type        = number
}

variable "management_port" {
  description = "Backend 관리 포트 (헬스 체크)"
  type        = number
}

variable "domain_name" {
  description = "인증서 기본 도메인"
  type        = string
}

variable "subject_alternative_names" {
  description = "인증서 추가 도메인"
  type        = list(string)
  default     = []
}

variable "deletion_protection" {
  description = "ALB 삭제 방지"
  type        = bool
  default     = true
}

variable "test_allowed_cidrs" {
  description = "테스트용으로 ALB 443 접근을 허용할 CIDR 목록 (비우면 규칙 없음)"
  type        = list(string)
  default     = []
}
