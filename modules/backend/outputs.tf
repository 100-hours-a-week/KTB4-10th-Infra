output "service_name" {
  description = "Backend ECS Service 이름"
  value       = aws_ecs_service.backend.name
}

output "task_definition_family" {
  description = "Backend Task Definition family"
  value       = aws_ecs_task_definition.backend.family
}

output "log_group_name" {
  description = "Backend CloudWatch Log Group 이름"
  value       = aws_cloudwatch_log_group.backend.name
}

output "secret_parameter_names" {
  description = "비밀 값을 넣을 Parameter Store 이름 목록"
  value       = [for p in aws_ssm_parameter.secrets : p.name]
}
