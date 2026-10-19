output "instance_id" {
  description = "Monitoring 서버 인스턴스 ID"
  value       = aws_instance.monitoring.id
}

output "private_ip" {
  description = "Monitoring 서버 사설 IP (Grafana 포트 포워딩 대상)"
  value       = aws_instance.monitoring.private_ip
}

output "secret_parameter_names" {
  description = "직접 값을 입력해야 하는 Parameter Store 이름"
  value       = [for p in aws_ssm_parameter.secrets : p.name]
}
