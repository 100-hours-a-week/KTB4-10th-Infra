output "instance_id" {
  description = "RDS 인스턴스 ID"
  value       = aws_db_instance.main.id
}

output "address" {
  description = "RDS 엔드포인트 호스트"
  value       = aws_db_instance.main.address
}

output "port" {
  description = "RDS 포트"
  value       = aws_db_instance.main.port
}
