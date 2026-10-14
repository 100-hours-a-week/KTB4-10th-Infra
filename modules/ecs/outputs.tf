output "cluster_name" {
  description = "ECS Cluster 이름"
  value       = aws_ecs_cluster.main.name
}

output "cluster_arn" {
  description = "ECS Cluster ARN"
  value       = aws_ecs_cluster.main.arn
}

output "capacity_provider_name" {
  description = "ECS Capacity Provider 이름"
  value       = aws_ecs_capacity_provider.ecs.name
}

output "autoscaling_group_name" {
  description = "ECS Host ASG 이름"
  value       = aws_autoscaling_group.ecs.name
}
