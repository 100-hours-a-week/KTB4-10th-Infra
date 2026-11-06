# ---------- Route 53 (kguidebook.site, 콘솔에서 생성) ----------
# staging-alb 레코드는 staging/dns.tf에서 관리
# V1 레코드(backend, v1-test)와 V1 VPC 모니터링(staging-grafana)은 정리 예정이라 관리하지 않음

resource "aws_route53_zone" "main" {
  name    = "kguidebook.site"
  comment = ""
}

# 서비스 도메인 -> CloudFront
resource "aws_route53_record" "apex" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "kguidebook.site"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.main.domain_name
    zone_id                = aws_cloudfront_distribution.main.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "api" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "api.kguidebook.site"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.main.domain_name
    zone_id                = aws_cloudfront_distribution.main.hosted_zone_id
    evaluate_target_health = false
  }
}

# CloudFront 원본 -> prod ALB (ALB 인증서 도메인으로 HTTPS 연결)
resource "aws_route53_record" "api_origin" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "v2-api-origin.kguidebook.site"
  type    = "A"

  alias {
    name                   = "dualstack.${module.alb.alb_dns_name}"
    zone_id                = module.alb.alb_zone_id
    evaluate_target_health = true
  }
}

# ACM DNS 검증 (*.kguidebook.site, CloudFront 인증서와 ALB 인증서가 같이 사용)
resource "aws_route53_record" "acm_validation" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "_faffad4697b12ca44885de9cd18c6c29.kguidebook.site"
  type    = "CNAME"
  ttl     = 6
  records = ["_636416dea1b3ae163f1ebcc4431b566a.wzccmgtwzk.acm-validations.aws."]
}

# 메일 (ImprovMX 전달)
resource "aws_route53_record" "mx" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "kguidebook.site"
  type    = "MX"
  ttl     = 300
  records = ["10 mx1.improvmx.com", "20 mx2.improvmx.com"]
}

resource "aws_route53_record" "spf" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "kguidebook.site"
  type    = "TXT"
  ttl     = 300
  records = ["v=spf1 include:spf.improvmx.com ~all"]
}

# ---------- GitHub Actions OIDC 공급자 (staging과 공용, prod에서만 관리) ----------
# modules/iam은 data로 조회해서 사용

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["ab9d0263244dd0326eb67015705a667e79cfe998"]
}
