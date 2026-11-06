# ---------- Route 53 레코드 (영역은 prod/dns.tf에서 관리) ----------

data "aws_route53_zone" "main" {
  name = "kguidebook.site"
}

# CloudFront 원본 -> staging ALB (ALB 인증서 도메인으로 HTTPS 연결)
resource "aws_route53_record" "alb" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "staging-alb.kguidebook.site"
  type    = "A"

  alias {
    name                   = "dualstack.${module.alb.alb_dns_name}"
    zone_id                = module.alb.alb_zone_id
    evaluate_target_health = false
  }
}
