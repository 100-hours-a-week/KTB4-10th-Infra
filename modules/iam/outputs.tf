output "ecs_instance_role_arn" {
  description = "ECS 인스턴스 역할 ARN"
  value       = aws_iam_role.ecs_instance.arn
}

output "ecs_instance_profile_name" {
  description = "ECS 인스턴스 프로파일 이름"
  value       = aws_iam_instance_profile.ecs_instance.name
}

output "task_execution_role_arn" {
  description = "태스크 실행 역할 ARN"
  value       = aws_iam_role.task_execution.arn
}

output "task_role_arn" {
  description = "태스크 역할 ARN"
  value       = aws_iam_role.task.arn
}

output "task_role_name" {
  description = "태스크 역할 이름 (정책 추가용)"
  value       = aws_iam_role.task.name
}

output "monitoring_instance_profile_name" {
  description = "Monitoring 인스턴스 프로파일 이름"
  value       = aws_iam_instance_profile.monitoring.name
}

output "github_backend_deploy_role_arn" {
  description = "백엔드 GitHub Actions 배포 역할 ARN"
  value       = aws_iam_role.github_backend_deploy.arn
}

output "github_frontend_deploy_role_arn" {
  description = "프론트엔드 GitHub Actions 배포 역할 ARN"
  value       = aws_iam_role.github_frontend_deploy.arn
}
