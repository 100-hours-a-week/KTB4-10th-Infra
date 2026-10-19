# CloudFront origin-facing IP 대역 (AWS 관리형 Prefix List)
data "aws_ec2_managed_prefix_list" "cloudfront" {
  name = "com.amazonaws.global.cloudfront.origin-facing"
}

# ALB SG
resource "aws_security_group" "alb" {
  name        = "${var.name}-alb-sg"
  description = "ALB security group"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.name}-alb-sg"
  }
}

# ECS Host SG (bridge 모드. Backend 컨테이너도 사용)
resource "aws_security_group" "ecs_host" {
  name        = "${var.name}-ecs-host-sg"
  description = "ECS host security group"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.name}-ecs-host-sg"
  }
}

# RDS SG (아웃바운드 규칙 없음)
resource "aws_security_group" "rds" {
  name        = "${var.name}-rds-sg"
  description = "RDS security group"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.name}-rds-sg"
  }
}

# Monitoring SG
resource "aws_security_group" "monitoring" {
  name        = "${var.name}-monitoring-sg"
  description = "Monitoring security group"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.name}-monitoring-sg"
  }
}

# NAT SG (AZ별 인스턴스가 같이 사용)
resource "aws_security_group" "nat" {
  name        = "${var.name}-nat-sg"
  description = "NAT instance security group"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.name}-nat-sg"
  }
}

# AI SG 
resource "aws_security_group" "ai" {
  name        = "${var.name}-ai-sg"
  description = "AI host security group"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.name}-ai-sg"
  }
}

# ---------- ALB ----------

# CloudFront -> ALB
resource "aws_vpc_security_group_ingress_rule" "alb_https_from_cloudfront" {
  security_group_id = aws_security_group.alb.id
  description       = "Allow HTTPS 443 from CloudFront to ALB"

  ip_protocol    = "tcp"
  from_port      = 443
  to_port        = 443
  prefix_list_id = data.aws_ec2_managed_prefix_list.cloudfront.id
}

# ALB -> ECS Host (Backend API)
resource "aws_vpc_security_group_egress_rule" "alb_to_ecs_host_app" {
  security_group_id = aws_security_group.alb.id
  description       = "Allow traffic from ALB to backend application port"

  ip_protocol                  = "tcp"
  from_port                    = var.app_port
  to_port                      = var.app_port
  referenced_security_group_id = aws_security_group.ecs_host.id
}

# ALB -> ECS Host (Backend health check)
resource "aws_vpc_security_group_egress_rule" "alb_to_ecs_host_management" {
  security_group_id = aws_security_group.alb.id
  description       = "Allow health check from ALB to backend management port"

  ip_protocol                  = "tcp"
  from_port                    = var.management_port
  to_port                      = var.management_port
  referenced_security_group_id = aws_security_group.ecs_host.id
}

# ---------- ECS Host ----------

# ALB -> ECS Host (Backend API)
resource "aws_vpc_security_group_ingress_rule" "ecs_host_app_from_alb" {
  security_group_id = aws_security_group.ecs_host.id
  description       = "Allow backend application port from ALB"

  ip_protocol                  = "tcp"
  from_port                    = var.app_port
  to_port                      = var.app_port
  referenced_security_group_id = aws_security_group.alb.id
}

# ALB -> ECS Host (Backend health check)
resource "aws_vpc_security_group_ingress_rule" "ecs_host_management_from_alb" {
  security_group_id = aws_security_group.ecs_host.id
  description       = "Allow backend health check from ALB"

  ip_protocol                  = "tcp"
  from_port                    = var.management_port
  to_port                      = var.management_port
  referenced_security_group_id = aws_security_group.alb.id
}

# Monitoring -> ECS Host (Backend Actuator 메트릭 수집)
resource "aws_vpc_security_group_ingress_rule" "ecs_host_management_from_monitoring" {
  security_group_id = aws_security_group.ecs_host.id
  description       = "Allow backend actuator scrape from monitoring"

  ip_protocol                  = "tcp"
  from_port                    = var.management_port
  to_port                      = var.management_port
  referenced_security_group_id = aws_security_group.monitoring.id
}

# Monitoring -> ECS Host (node-exporter)
resource "aws_vpc_security_group_ingress_rule" "ecs_host_node_exporter_from_monitoring" {
  security_group_id = aws_security_group.ecs_host.id
  description       = "Allow node-exporter scrape from monitoring"

  ip_protocol                  = "tcp"
  from_port                    = var.node_exporter_port
  to_port                      = var.node_exporter_port
  referenced_security_group_id = aws_security_group.monitoring.id
}

# Monitoring -> ECS Host (cAdvisor, Backend 관리 포트와 겹치지 않게 별도 포트)
resource "aws_vpc_security_group_ingress_rule" "ecs_host_cadvisor_from_monitoring" {
  security_group_id = aws_security_group.ecs_host.id
  description       = "Allow cAdvisor scrape from monitoring"

  ip_protocol                  = "tcp"
  from_port                    = var.cadvisor_port
  to_port                      = var.cadvisor_port
  referenced_security_group_id = aws_security_group.monitoring.id
}

# ECS Host -> RDS (Backend 컨테이너)
resource "aws_vpc_security_group_egress_rule" "ecs_host_to_rds" {
  security_group_id = aws_security_group.ecs_host.id
  description       = "Allow MySQL from backend container to RDS"

  ip_protocol                  = "tcp"
  from_port                    = 3306
  to_port                      = 3306
  referenced_security_group_id = aws_security_group.rds.id
}

# ECS Host -> 외부 HTTPS (ECS 에이전트, 이미지 다운로드, Backend 외부 API)
resource "aws_vpc_security_group_egress_rule" "ecs_host_https" {
  security_group_id = aws_security_group.ecs_host.id
  description       = "Allow HTTPS for ECS agent and image pull"

  ip_protocol = "tcp"
  from_port   = 443
  to_port     = 443
  cidr_ipv4   = "0.0.0.0/0"
}

# ECS Host -> AI (Backend 컨테이너가 AI 호출)
resource "aws_vpc_security_group_egress_rule" "ecs_host_to_ai" {
  security_group_id = aws_security_group.ecs_host.id
  description       = "Allow backend container to call AI server"

  ip_protocol                  = "tcp"
  from_port                    = var.ai_port
  to_port                      = var.ai_port
  referenced_security_group_id = aws_security_group.ai.id
}

# ---------- AI ----------

# ECS Host -> AI (/metrics 포함 전체 경로라 Backend와 Monitoring 외에는 열지 않음)
resource "aws_vpc_security_group_ingress_rule" "ai_from_ecs_host" {
  security_group_id = aws_security_group.ai.id
  description       = "Allow AI port from backend container on ECS host"

  ip_protocol                  = "tcp"
  from_port                    = var.ai_port
  to_port                      = var.ai_port
  referenced_security_group_id = aws_security_group.ecs_host.id
}

# Monitoring -> AI (node-exporter)
resource "aws_vpc_security_group_ingress_rule" "ai_node_exporter_from_monitoring" {
  security_group_id = aws_security_group.ai.id
  description       = "Allow node-exporter scrape from monitoring"

  ip_protocol                  = "tcp"
  from_port                    = var.node_exporter_port
  to_port                      = var.node_exporter_port
  referenced_security_group_id = aws_security_group.monitoring.id
}

# Monitoring -> AI (cAdvisor)
resource "aws_vpc_security_group_ingress_rule" "ai_cadvisor_from_monitoring" {
  security_group_id = aws_security_group.ai.id
  description       = "Allow cAdvisor scrape from monitoring"

  ip_protocol                  = "tcp"
  from_port                    = var.cadvisor_port
  to_port                      = var.cadvisor_port
  referenced_security_group_id = aws_security_group.monitoring.id
}

# Monitoring -> AI (/metrics 수집. 내부 Monitoring SG에만 허용)
resource "aws_vpc_security_group_ingress_rule" "ai_metrics_from_monitoring" {
  security_group_id = aws_security_group.ai.id
  description       = "Allow AI metrics scrape from monitoring"

  ip_protocol                  = "tcp"
  from_port                    = var.ai_port
  to_port                      = var.ai_port
  referenced_security_group_id = aws_security_group.monitoring.id
}

# AI -> 외부 HTTPS (ECS 에이전트, 이미지 다운로드, SSM, 향후 RunPod)
resource "aws_vpc_security_group_egress_rule" "ai_https" {
  security_group_id = aws_security_group.ai.id
  description       = "Allow HTTPS for ECS agent, image pull and external APIs"

  ip_protocol = "tcp"
  from_port   = 443
  to_port     = 443
  cidr_ipv4   = "0.0.0.0/0"
}

# ---------- RDS ----------

# ECS Host -> RDS (Backend 컨테이너)
resource "aws_vpc_security_group_ingress_rule" "rds_mysql_from_ecs_host" {
  security_group_id = aws_security_group.rds.id
  description       = "Allow MySQL from backend container on ECS host"

  ip_protocol                  = "tcp"
  from_port                    = 3306
  to_port                      = 3306
  referenced_security_group_id = aws_security_group.ecs_host.id
}

# Monitoring -> RDS (mysqld-exporter)
resource "aws_vpc_security_group_ingress_rule" "rds_mysql_from_monitoring" {
  security_group_id = aws_security_group.rds.id
  description       = "Allow MySQL from mysqld-exporter on monitoring"

  ip_protocol                  = "tcp"
  from_port                    = 3306
  to_port                      = 3306
  referenced_security_group_id = aws_security_group.monitoring.id
}

# NAT -> RDS (운영자 SSM 포트 포워딩)
resource "aws_vpc_security_group_ingress_rule" "rds_mysql_from_nat" {
  security_group_id = aws_security_group.rds.id
  description       = "Allow MySQL from NAT instance via SSM port forwarding"

  ip_protocol                  = "tcp"
  from_port                    = 3306
  to_port                      = 3306
  referenced_security_group_id = aws_security_group.nat.id
}

# ---------- Monitoring ----------

# NAT -> Monitoring (Grafana SSM 포트 포워딩)
resource "aws_vpc_security_group_ingress_rule" "monitoring_grafana_from_nat" {
  security_group_id = aws_security_group.monitoring.id
  description       = "Allow Grafana from NAT instance via SSM port forwarding"

  ip_protocol                  = "tcp"
  from_port                    = 3000
  to_port                      = 3000
  referenced_security_group_id = aws_security_group.nat.id
}

# Monitoring -> ECS Host (node-exporter)
resource "aws_vpc_security_group_egress_rule" "monitoring_to_node_exporter" {
  security_group_id = aws_security_group.monitoring.id
  description       = "Allow node-exporter scrape to ECS host"

  ip_protocol                  = "tcp"
  from_port                    = var.node_exporter_port
  to_port                      = var.node_exporter_port
  referenced_security_group_id = aws_security_group.ecs_host.id
}

# Monitoring -> ECS Host (cAdvisor)
resource "aws_vpc_security_group_egress_rule" "monitoring_to_cadvisor" {
  security_group_id = aws_security_group.monitoring.id
  description       = "Allow cAdvisor scrape to ECS host"

  ip_protocol                  = "tcp"
  from_port                    = var.cadvisor_port
  to_port                      = var.cadvisor_port
  referenced_security_group_id = aws_security_group.ecs_host.id
}

# Monitoring -> ECS Host (Backend Actuator 메트릭 수집)
resource "aws_vpc_security_group_egress_rule" "monitoring_to_ecs_host_management" {
  security_group_id = aws_security_group.monitoring.id
  description       = "Allow backend actuator scrape to ECS host"

  ip_protocol                  = "tcp"
  from_port                    = var.management_port
  to_port                      = var.management_port
  referenced_security_group_id = aws_security_group.ecs_host.id
}

# Monitoring -> AI (node-exporter)
resource "aws_vpc_security_group_egress_rule" "monitoring_to_ai_node_exporter" {
  security_group_id = aws_security_group.monitoring.id
  description       = "Allow node-exporter scrape to AI host"

  ip_protocol                  = "tcp"
  from_port                    = var.node_exporter_port
  to_port                      = var.node_exporter_port
  referenced_security_group_id = aws_security_group.ai.id
}

# Monitoring -> AI (cAdvisor)
resource "aws_vpc_security_group_egress_rule" "monitoring_to_ai_cadvisor" {
  security_group_id = aws_security_group.monitoring.id
  description       = "Allow cAdvisor scrape to AI host"

  ip_protocol                  = "tcp"
  from_port                    = var.cadvisor_port
  to_port                      = var.cadvisor_port
  referenced_security_group_id = aws_security_group.ai.id
}

# Monitoring -> AI (/metrics)
resource "aws_vpc_security_group_egress_rule" "monitoring_to_ai_metrics" {
  security_group_id = aws_security_group.monitoring.id
  description       = "Allow AI metrics scrape to AI host"

  ip_protocol                  = "tcp"
  from_port                    = var.ai_port
  to_port                      = var.ai_port
  referenced_security_group_id = aws_security_group.ai.id
}

# Monitoring -> RDS (mysqld-exporter)
resource "aws_vpc_security_group_egress_rule" "monitoring_to_rds" {
  security_group_id = aws_security_group.monitoring.id
  description       = "Allow MySQL from mysqld-exporter to RDS"

  ip_protocol                  = "tcp"
  from_port                    = 3306
  to_port                      = 3306
  referenced_security_group_id = aws_security_group.rds.id
}

# Monitoring -> 외부 HTTPS
resource "aws_vpc_security_group_egress_rule" "monitoring_https" {
  security_group_id = aws_security_group.monitoring.id
  description       = "Allow HTTPS for package install and alerting"

  ip_protocol = "tcp"
  from_port   = 443
  to_port     = 443
  cidr_ipv4   = "0.0.0.0/0"
}

# ---------- NAT ----------

# Private app subnet -> NAT
resource "aws_vpc_security_group_ingress_rule" "nat_https_from_private_app" {
  for_each = toset(var.private_app_subnet_cidrs)

  security_group_id = aws_security_group.nat.id
  description       = "Allow HTTPS from private app subnet for NAT"

  ip_protocol = "tcp"
  from_port   = 443
  to_port     = 443
  cidr_ipv4   = each.value
}

# NAT -> Monitoring (Grafana SSM 포트 포워딩)
resource "aws_vpc_security_group_egress_rule" "nat_grafana_to_monitoring" {
  security_group_id = aws_security_group.nat.id
  description       = "Allow Grafana SSM port forwarding to monitoring"

  ip_protocol                  = "tcp"
  from_port                    = 3000
  to_port                      = 3000
  referenced_security_group_id = aws_security_group.monitoring.id
}

# NAT -> RDS (운영자 SSM 포트 포워딩)
resource "aws_vpc_security_group_egress_rule" "nat_mysql_to_rds" {
  security_group_id = aws_security_group.nat.id
  description       = "Allow MySQL SSM port forwarding to RDS"

  ip_protocol                  = "tcp"
  from_port                    = 3306
  to_port                      = 3306
  referenced_security_group_id = aws_security_group.rds.id
}

# NAT -> 인터넷
resource "aws_vpc_security_group_egress_rule" "nat_https" {
  security_group_id = aws_security_group.nat.id
  description       = "Allow HTTPS to internet for NAT"

  ip_protocol = "tcp"
  from_port   = 443
  to_port     = 443
  cidr_ipv4   = "0.0.0.0/0"
}
