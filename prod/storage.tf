# ---------- Backend 파일 저장소 (콘솔에서 생성, Tour API 스냅샷과 /tourism/* 파일) ----------

resource "aws_s3_bucket" "backend_storage" {
  bucket = var.backend_storage_bucket_name
}

resource "aws_s3_bucket_public_access_block" "backend_storage" {
  bucket = aws_s3_bucket.backend_storage.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "backend_storage" {
  bucket = aws_s3_bucket.backend_storage.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "backend_storage" {
  bucket = aws_s3_bucket.backend_storage.id

  rule {
    blocked_encryption_types = ["SSE-C"]
    bucket_key_enabled       = true

    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# CloudFront 배포에서 tourism/* 만 읽기 허용 (cloudfront.tf의 /tourism/* 경로)
resource "aws_s3_bucket_policy" "backend_storage" {
  bucket = aws_s3_bucket.backend_storage.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowCloudFrontServicePrincipalReadOnly"
      Effect    = "Allow"
      Principal = { Service = "cloudfront.amazonaws.com" }
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.backend_storage.arn}/tourism/*"
      Condition = {
        StringEquals = {
          "AWS:SourceArn" = aws_cloudfront_distribution.main.arn
        }
      }
    }]
  })
}
