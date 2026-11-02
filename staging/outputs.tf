# 콘솔 작업(Peering 경로, CloudFront 원본, Route 53, Prometheus 대상)에 필요한 값

output "vpc_id" {
  description = "staging VPC ID (Peering 수락 대상)"
  value       = module.network.vpc_id
}

output "private_app_route_table_ids" {
  description = "V1 테스트 VPC(10.0.0.0/16) 경로를 추가할 route table (App)"
  value       = module.network.private_app_route_table_ids
}

output "private_db_route_table_id" {
  description = "V1 테스트 VPC(10.0.0.0/16) 경로를 추가할 route table (DB)"
  value       = module.network.private_db_route_table_id
}

output "alb_dns_name" {
  description = "staging-alb.kguidebook.site 레코드가 가리킬 ALB 주소"
  value       = module.alb.alb_dns_name
}

output "alb_zone_id" {
  description = "Route 53 alias 레코드용 ALB Hosted Zone ID"
  value       = module.alb.alb_zone_id
}

output "rds_address" {
  description = "staging RDS 엔드포인트 (V1 테스트 Backend DB 주소)"
  value       = module.rds.address
}

output "ai_private_ip" {
  description = "AI 서버 사설 IP (Prometheus 수집 대상)"
  value       = module.ai.private_ip
}

output "ecs_autoscaling_group_name" {
  description = "Backend ECS Host ASG 이름 (서버 IP 조회용)"
  value       = module.ecs.autoscaling_group_name
}

output "nat_instance_ids" {
  description = "SSM 포트 포워딩용 NAT 인스턴스 ID"
  value       = module.nat.instance_ids
}

output "secret_parameter_names" {
  description = "값을 직접 넣을 Parameter Store, Secrets Manager 이름"
  value = {
    backend = module.backend.secret_parameter_names
    ai      = module.ai.secret_parameter_names
    ghcr    = module.registry.ghcr_secret_name
  }
}

output "github_deploy_role_arns" {
  description = "GitHub Actions 배포 역할 ARN (워크플로 role-to-assume)"
  value = {
    backend  = module.iam.github_backend_deploy_role_arn
    ai       = module.iam.github_ai_deploy_role_arn
    frontend = module.iam.github_frontend_deploy_role_arn
  }
}
