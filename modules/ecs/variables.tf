variable "name" {
  description = "리소스 식별 이름"
  type        = string
}

variable "subnet_ids" {
  description = "ECS Host를 둘 private-app subnet ID 목록"
  type        = list(string)
}

variable "security_group_id" {
  description = "ECS Host security group ID"
  type        = string
}

variable "instance_profile_name" {
  description = "ECS Host instance profile 이름"
  type        = string
}

variable "ami_ssm_parameter_name" {
  description = "ECS 최적화 AMI ID를 조회할 SSM 파라미터 이름"
  type        = string
  default     = "/aws/service/ecs/optimized-ami/amazon-linux-2023/recommended/image_id"
}

variable "instance_type" {
  description = "ECS Host 인스턴스 타입"
  type        = string
}

variable "root_volume_size" {
  description = "ECS Host 루트 볼륨 크기 (GiB, AMI 기본값 30 이상)"
  type        = number
  default     = 30
}

variable "min_size" {
  description = "ASG 최소 인스턴스 수"
  type        = number
}

variable "max_size" {
  description = "ASG 최대 인스턴스 수 (배포용 임시 용량 포함)"
  type        = number
}

variable "desired_capacity" {
  description = "ASG 초기 인스턴스 수 (이후 변경은 무시)"
  type        = number
}
