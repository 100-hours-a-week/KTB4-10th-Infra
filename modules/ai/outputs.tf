output "private_ip" {
  description = "AI 서버 사설 IP"
  value       = aws_instance.ai.private_ip
}

output "base_url" {
  description = "Backend가 호출할 AI 주소"
  value       = "http://${aws_instance.ai.private_ip}:${var.port}"
}

output "instance_id" {
  description = "AI 서버 인스턴스 ID"
  value       = aws_instance.ai.id
}

output "service_name" {
  description = "AI ECS Service 이름"
  value       = aws_ecs_service.ai.name
}

output "secret_parameter_names" {
  description = "비밀 값을 넣을 Parameter Store 이름 목록"
  value       = [for p in aws_ssm_parameter.secrets : p.name]
}
