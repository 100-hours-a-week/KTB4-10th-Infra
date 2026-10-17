output "alb_dns_name" {
  description = "ALB DNS 이름 (CloudFront 오리진, Route 53 alias 대상)"
  value       = aws_lb.main.dns_name
}

output "alb_zone_id" {
  description = "ALB Hosted Zone ID (Route 53 alias용)"
  value       = aws_lb.main.zone_id
}

output "target_group_arn" {
  description = "Backend Target Group ARN"
  value       = aws_lb_target_group.backend.arn
}

output "certificate_arn" {
  description = "ALB용 ACM 인증서 ARN"
  value       = aws_acm_certificate.main.arn
}
