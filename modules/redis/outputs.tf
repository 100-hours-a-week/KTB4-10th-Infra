output "primary_endpoint_address" {
  description = "Redis Primary 엔드포인트 호스트"
  value       = aws_elasticache_replication_group.main.primary_endpoint_address
}

output "port" {
  description = "Redis 포트"
  value       = aws_elasticache_replication_group.main.port
}

output "auth_token_secret_arn" {
  description = "Redis 인증 토큰 Secrets Manager ARN"
  value       = aws_secretsmanager_secret.auth_token.arn
}
