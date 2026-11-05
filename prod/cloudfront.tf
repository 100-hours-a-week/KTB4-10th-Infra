# ---------- CloudFront (kguidebook.site, 콘솔에서 생성) ----------
# 프론트엔드(S3) 서빙 + /api/*, /auth/v1/* 는 V2 ALB, /tourism/* 는 Backend 저장소 버킷

locals {
  # AWS 관리형 정책 ID
  cloudfront_cache_optimized    = "658327ea-f89d-4fab-a63d-7e88639e58f6" # Managed-CachingOptimized
  cloudfront_cache_disabled     = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad" # Managed-CachingDisabled
  cloudfront_all_viewer         = "216adef6-5c7f-47e4-b989-5492eafa07d3" # Managed-AllViewer
  cloudfront_security_headers   = "67f7725c-6f97-4210-82d7-5512b31e9d03" # Managed-SecurityHeadersPolicy
  cloudfront_frontend_origin_id = "kgb-frontend.s3.ap-northeast-2.amazonaws.com-mu3py7bi9j0"
  cloudfront_storage_origin_id  = "kgb-s3-storage.s3.ap-northeast-2.amazonaws.com"
  cloudfront_api_origin_id      = "v2-alb"
}

# CloudFront용 인증서 (us-east-1, DNS 검증)
resource "aws_acm_certificate" "cloudfront" {
  provider = aws.us_east_1

  domain_name               = "kguidebook.site"
  subject_alternative_names = ["*.kguidebook.site", "kguidebook.site"]
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_cloudfront_origin_access_control" "frontend" {
  name                              = "oac-kgb-frontend.s3.ap-northeast-2.amazonaws.com-mu3q0j4t5eh"
  description                       = "Created by CloudFront"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_origin_access_control" "storage" {
  name                              = "kgb-s3-storage-oac"
  description                       = "OAC for KGB storage bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# 확장자가 없는 경로는 SPA route로 보고 index.html 반환 (staging 배포도 사용)
resource "aws_cloudfront_function" "spa_rewrite" {
  name    = "kgb-spa-rewrite"
  runtime = "cloudfront-js-2.0"
  publish = true
  code = chomp(<<-EOT
    function handler(event) {
        var request = event.request;
        var uri = request.uri;

        // 확장자가 없는 경로는 React SPA route로 보고 index.html 반환
        if (!uri.includes('.')) {
            request.uri = '/index.html';
        }

        return request;
    }
  EOT
  )
}

resource "aws_cloudfront_distribution" "main" {
  enabled             = true
  comment             = "리버스 프록시 및 프론트엔드 서빙용도"
  aliases             = ["api.kguidebook.site", "kguidebook.site"]
  default_root_object = "index.html"
  http_version        = "http2"
  is_ipv6_enabled     = true
  price_class         = "PriceClass_All"

  # CloudFront 콘솔이 만든 WAF (us-east-1, Terraform 미관리)
  web_acl_id = "arn:aws:wafv2:us-east-1:742875367096:global/webacl/CreatedByCloudFront-7c97e6ba/e2d850c9-e9a5-4d51-ad3f-b22617fd4728"

  origin {
    origin_id                = local.cloudfront_frontend_origin_id
    domain_name              = aws_s3_bucket.frontend.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.frontend.id
  }

  origin {
    origin_id                = local.cloudfront_storage_origin_id
    domain_name              = aws_s3_bucket.backend_storage.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.storage.id
  }

  # V2 ALB (ALB 인증서 도메인으로 HTTPS 연결)
  origin {
    origin_id   = local.cloudfront_api_origin_id
    domain_name = "v2-api-origin.kguidebook.site"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
      ip_address_type        = "ipv4"
      origin_read_timeout    = 60
    }
  }

  default_cache_behavior {
    target_origin_id           = local.cloudfront_frontend_origin_id
    viewer_protocol_policy     = "redirect-to-https"
    allowed_methods            = ["GET", "HEAD"]
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    cache_policy_id            = local.cloudfront_cache_optimized
    response_headers_policy_id = local.cloudfront_security_headers

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.spa_rewrite.arn
    }
  }

  ordered_cache_behavior {
    path_pattern             = "/api/*"
    target_origin_id         = local.cloudfront_api_origin_id
    viewer_protocol_policy   = "redirect-to-https"
    allowed_methods          = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods           = ["GET", "HEAD"]
    compress                 = true
    cache_policy_id          = local.cloudfront_cache_disabled
    origin_request_policy_id = local.cloudfront_all_viewer
  }

  ordered_cache_behavior {
    path_pattern             = "/auth/v1/*"
    target_origin_id         = local.cloudfront_api_origin_id
    viewer_protocol_policy   = "redirect-to-https"
    allowed_methods          = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods           = ["GET", "HEAD"]
    compress                 = true
    cache_policy_id          = local.cloudfront_cache_disabled
    origin_request_policy_id = local.cloudfront_all_viewer
  }

  ordered_cache_behavior {
    path_pattern           = "/tourism/*"
    target_origin_id       = local.cloudfront_storage_origin_id
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true
    cache_policy_id        = local.cloudfront_cache_optimized
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate.cloudfront.arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.3_2025"
  }

  tags = {
    Name = "ktb4-10-cloudfront"
  }
}
