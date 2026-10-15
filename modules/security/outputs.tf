output "alb_security_group_id" {
  description = "ALB security group ID"
  value       = aws_security_group.alb.id
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

output "nat_security_group_id" {
  description = "NAT instance security group ID"
  value       = aws_security_group.nat.id
}
