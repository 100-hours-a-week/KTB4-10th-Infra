variable "name" {
  description = "리소스 식별 이름"
  type        = string
}

variable "cidr" {
  description = "VPC에서 사용할 CIDR 블록"
  type        = string
}

variable "azs" {
  description = "AZ 목록"
  type        = list(string)
}

variable "public_subnets" {
  description = "public subnet으로 사용할 CIDR 블록 목록 (azs와 같은 순서)"
  type        = list(string)
}

variable "private_app_subnets" {
  description = "Backend Private subnet CIDR 블록 목록 (azs와 같은 순서)"
  type        = list(string)
}

variable "private_db_subnets" {
  description = "Database Private subnet CIDR 블록 목록 (azs와 같은 순서)"
  type        = list(string)
}
