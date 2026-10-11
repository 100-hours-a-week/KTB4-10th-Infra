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

variable "operator_cidrs" {
  description = "Bastion SSH를 허용할 운영자 공인 IP CIDR 목록 (/32)"
  type        = list(string)
}
