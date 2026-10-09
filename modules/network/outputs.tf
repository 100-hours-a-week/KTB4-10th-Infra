output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "public subnet ID 목록"
  value       = aws_subnet.public[*].id
}

output "private_app_subnet_ids" {
  description = "Backend Private subnet ID 목록"
  value       = aws_subnet.private_app[*].id
}

output "private_db_subnet_ids" {
  description = "Database Private subnet ID 목록"
  value       = aws_subnet.private_db[*].id
}

output "public_route_table_id" {
  description = "public route table ID"
  value       = aws_route_table.public.id
}

output "private_app_route_table_ids" {
  description = "Backend Private route table ID"
  value       = aws_route_table.private_app[*].id
}

output "private_db_route_table_id" {
  description = "Database Private route table ID"
  value       = aws_route_table.private_db.id
}

