output "ghcr_secret_arn" {
  description = "GHCR 인증 정보 Secrets Manager ARN"
  value       = aws_secretsmanager_secret.ghcr.arn
}

output "ghcr_secret_name" {
  description = "GHCR 인증 정보를 넣을 Secrets Manager 시크릿 이름"
  value       = aws_secretsmanager_secret.ghcr.name
}
