output "alb_security_group_id" {
  description = "ALB security group ID"
  value       = aws_security_group.alb.id
}

output "backend_task_security_group_id" {
  description = "Backend task security group ID"
  value       = aws_security_group.backend_task.id
}

output "ecs_host_security_group_id" {
  description = "ECS host security group ID"
  value       = aws_security_group.ecs_host.id
}

output "rds_security_group_id" {
  description = "RDS security group ID"
  value       = aws_security_group.rds.id
}

output "monitoring_security_group_id" {
  description = "Monitoring security group ID"
  value       = aws_security_group.monitoring.id
}

output "nat_bastion_security_group_id" {
  description = "NAT/Bastion security group ID"
  value       = aws_security_group.nat_bastion.id
}
