output "node_exporter_service_name" {
  description = "node-exporter ECS Service 이름"
  value       = aws_ecs_service.node_exporter.name
}

output "cadvisor_service_name" {
  description = "cAdvisor ECS Service 이름"
  value       = aws_ecs_service.cadvisor.name
}
