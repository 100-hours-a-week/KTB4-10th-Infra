variable "name" {
  description = "리소스 식별 이름"
  type        = string
}

variable "azs" {
  description = "AZ 목록"
  type        = list(string)
}

variable "public_subnet_ids" {
  description = "NAT 인스턴스를 둘 public subnet ID 목록 (azs와 같은 순서)"
  type        = list(string)
}

variable "private_app_route_table_ids" {
  description = "NAT 경로를 추가할 Backend Private route table ID 목록 (azs와 같은 순서)"
  type        = list(string)
}

variable "security_group_id" {
  description = "NAT security group ID"
  type        = string
}

variable "ami_id" {
  description = "NAT 인스턴스 AMI ID (Ubuntu, x86_64)"
  type        = string
}

variable "instance_type" {
  description = "NAT 인스턴스 타입 (x86_64)"
  type        = string
}

variable "instance_profile_name" {
  description = "NAT 인스턴스 프로파일 이름 (Session Manager 접속용)"
  type        = string
}

# false면 인스턴스 자동 공인 IP 사용 (EIP 한도와 무관, 중지 후 시작하면 IP가 바뀜)
variable "use_eip" {
  description = "NAT 공인 IP로 EIP 사용"
  type        = bool
  default     = true
}
