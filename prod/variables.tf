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

variable "github_backend_subjects" {
  description = "백엔드  GitHub Actions OIDC Subject"
  type        = list(string)
}

variable "github_frontend_subjects" {
  description = "프론트엔드 GitHub Actions OIDC Subject"
  type        = list(string)
}

variable "frontend_bucket_name" {
  description = "프론트엔드 배포용  S3 버킷 이름"
  type        = string
}

variable "frontend_cloudfront_distribution_id" {
  description = "프론트엔드 배포용 CloudFront Distribution ID"
  type        = string
}

# ubuntu-resolute-26.04-amd64-server-20261003 (ap-northeast-2)
variable "nat_ami_id" {
  description = "NAT 인스턴스 AMI ID (Ubuntu 26.04, x86_64)"
  type        = string
  default     = "ami-0e677ebf2c8434c2a"
}

variable "nat_instance_type" {
  description = "NAT 인스턴스 타입 (x86_64)"
  type        = string
  default     = "t3.micro"
}
