# ---------- CloudFront (staging, 콘솔에서 생성) ----------
# 프론트엔드(S3) 서빙 + /api/*, /auth/v1/* 는 staging ALB

locals {
  # AWS 관리형 정책 ID
  cloudfront_cache_optimized    = "658327ea-f89d-4fab-a63d-7e88639e58f6" # Managed-CachingOptimized
  cloudfront_cache_disabled     = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad" # Managed-CachingDisabled
  cloudfront_all_viewer         = "216adef6-5c7f-47e4-b989-5492eafa07d3" # Managed-AllViewer
  cloudfront_frontend_origin_id = "kgb-staging-frontend.s3.ap-northeast-2.amazonaws.com"
  cloudfront_api_origin_id      = "v2-alb"

  # SPA 경로 함수는 prod에서 관리 (prod/cloudfront.tf)
  cloudfront_spa_rewrite_arn = "arn:aws:cloudfront::${data.aws_caller_identity.current.account_id}:function/kgb-spa-rewrite"
}

resource "aws_cloudfront_origin_access_control" "frontend" {
  name                              = "kgb-staging-frontend-oac"
  description                       = "OAC for kgb-staging-frontend S3 bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "main" {
  enabled             = true
  comment             = "staging"
  default_root_object = "index.html"
  http_version        = "http2"
  is_ipv6_enabled     = true
  price_class         = "PriceClass_All"

  # CloudFront 콘솔이 만든 WAF (us-east-1, Terraform 미관리)
  web_acl_id = "arn:aws:wafv2:us-east-1:742875367096:global/webacl/CreatedByCloudFront-5e55b53d/0e8df206-036b-4021-8158-48574dc3e05f"

  origin {
    origin_id                = local.cloudfront_frontend_origin_id
    domain_name              = aws_s3_bucket.frontend.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.frontend.id
  }

  # staging ALB (ALB 인증서 도메인으로 HTTPS 연결)
  origin {
    origin_id   = local.cloudfront_api_origin_id
    domain_name = "staging-alb.kguidebook.site"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
      ip_address_type        = "ipv4"
    }
  }

  default_cache_behavior {
    target_origin_id       = local.cloudfront_frontend_origin_id
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true
    cache_policy_id        = local.cloudfront_cache_optimized

    function_association {
      event_type   = "viewer-request"
      function_arn = local.cloudfront_spa_rewrite_arn
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

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = {
    Name = "kgb-staging-api"
  }
}
