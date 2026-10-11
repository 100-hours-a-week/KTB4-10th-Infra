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
