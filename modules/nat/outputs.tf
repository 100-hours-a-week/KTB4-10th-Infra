output "instance_ids" {
  description = "NAT 인스턴스 ID 목록"
  value       = aws_instance.nat[*].id
}

output "public_ips" {
  description = "NAT 공인 IP 목록"
  value       = var.use_eip ? aws_eip.nat[*].public_ip : aws_instance.nat[*].public_ip
}
