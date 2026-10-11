variable "name" {
  description = "리소스 식별 이름"
  type        = string
}

variable "github_backend_subjects" {
  description = "백엔드 배포 역할을 Assume할 수 있는 GitHub OIDC subject 목록)"
  type        = list(string)
}

variable "github_frontend_subjects" {
  description = "프론트엔드 배포를 허용할 GitHub OIDC Subject 목록"
  type        = list(string)
}

variable "frontend_bucket_name" {
  description = "프론트엔드 정적 파일을 배포할 S3 버킷 이름"
  type        = string
}

variable "frontend_cloudfront_distribution_id" {
  description = "프론트엔드 CloudFront Distribution ID"
  type        = string
}
