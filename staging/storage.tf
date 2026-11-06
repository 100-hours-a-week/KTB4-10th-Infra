# Backend 파일 저장소 (staging 전용, prod kgb-s3-storage와 분리)
resource "aws_s3_bucket" "backend_storage" {
  bucket = var.backend_storage_bucket_name
}

# 퍼블릭 접근 차단
resource "aws_s3_bucket_public_access_block" "backend_storage" {
  bucket = aws_s3_bucket.backend_storage.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Tour API 원본 스냅샷은 7일 뒤 삭제
resource "aws_s3_bucket_lifecycle_configuration" "backend_storage" {
  bucket = aws_s3_bucket.backend_storage.id

  rule {
    id     = "expire-tour-api-snapshots"
    status = "Enabled"

    filter {
      prefix = "tour-api/raw/"
    }

    expiration {
      days = 7
    }
  }
}
