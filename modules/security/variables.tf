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

variable "private_app_subnet_cidrs" {
  description = "NAT를 사용하는 Backend Private subnet CIDR 블록 목록"
  type        = list(string)
}

variable "operator_cidrs" {
  description = "Bastion SSH를 허용할 운영자 공인 IP CIDR 목록 (/32)"
  type        = list(string)
}
