variable "name" {
  description = "리소스 식별 이름"
  type        = string
}

variable "github_backend_subjects" {
  description = "백엔드 배포 역할을 Assume할 수 있는 GitHub OIDC subject 목록 (비우면 역할을 만들지 않음)"
  type        = list(string)
  default     = []
}

variable "github_frontend_subjects" {
  description = "프론트엔드 배포를 허용할 GitHub OIDC Subject 목록 (비우면 역할을 만들지 않음)"
  type        = list(string)
  default     = []
}

variable "frontend_bucket_name" {
  description = "프론트엔드 정적 파일을 배포할 S3 버킷 이름"
  type        = string
  default     = null

  validation {
    condition     = length(var.github_frontend_subjects) == 0 || var.frontend_bucket_name != null
    error_message = "github_frontend_subjects를 지정하면 frontend_bucket_name도 필요합니다."
  }
}

variable "frontend_cloudfront_distribution_id" {
  description = "프론트엔드 CloudFront Distribution ID"
  type        = string
  default     = null

  validation {
    condition     = length(var.github_frontend_subjects) == 0 || var.frontend_cloudfront_distribution_id != null
    error_message = "github_frontend_subjects를 지정하면 frontend_cloudfront_distribution_id도 필요합니다."
  }
}

variable "backend_storage_bucket_name" {
  description = "Backend가 파일을 저장하는 S3 버킷 이름"
  type        = string
}

variable "nat_instance_ids" {
  description = "개발자 포트 포워딩을 허용할 NAT 인스턴스 ID 목록"
  type        = list(string)
}
