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

# Backend Task SG (awsvpc 모드의 태스크 ENI에 연결)
resource "aws_security_group" "backend_task" {
  name        = "${var.name}-backend-task-sg"
  description = "Backend task security group"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.name}-backend-task-sg"
  }
}

# ECS Host SG
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

# ALB -> Backend Task
resource "aws_vpc_security_group_egress_rule" "alb_to_backend_task" {
  security_group_id = aws_security_group.alb.id
  description       = "Allow traffic from ALB to backend application port"

  ip_protocol                  = "tcp"
  from_port                    = var.app_port
  to_port                      = var.app_port
  referenced_security_group_id = aws_security_group.backend_task.id
}

# ---------- Backend Task ----------

# ALB -> Backend Task
resource "aws_vpc_security_group_ingress_rule" "backend_task_app_from_alb" {
  security_group_id = aws_security_group.backend_task.id
  description       = "Allow application port from ALB"

  ip_protocol                  = "tcp"
  from_port                    = var.app_port
  to_port                      = var.app_port
  referenced_security_group_id = aws_security_group.alb.id
}

# Monitoring -> Backend Task (Actuator 메트릭 수집)
resource "aws_vpc_security_group_ingress_rule" "backend_task_app_from_monitoring" {
  security_group_id = aws_security_group.backend_task.id
  description       = "Allow actuator metrics scrape from monitoring"

  ip_protocol                  = "tcp"
  from_port                    = var.app_port
  to_port                      = var.app_port
  referenced_security_group_id = aws_security_group.monitoring.id
}

# Backend Task -> RDS
resource "aws_vpc_security_group_egress_rule" "backend_task_to_rds" {
  security_group_id = aws_security_group.backend_task.id
  description       = "Allow MySQL to RDS"

  ip_protocol                  = "tcp"
  from_port                    = 3306
  to_port                      = 3306
  referenced_security_group_id = aws_security_group.rds.id
}

# Backend Task -> 외부 HTTPS
resource "aws_vpc_security_group_egress_rule" "backend_task_https" {
  security_group_id = aws_security_group.backend_task.id
  description       = "Allow HTTPS to external APIs and AWS services"

  ip_protocol = "tcp"
  from_port   = 443
  to_port     = 443
  cidr_ipv4   = "0.0.0.0/0"
}

# ---------- ECS Host ----------

# Monitoring -> ECS Host (node-exporter)
resource "aws_vpc_security_group_ingress_rule" "ecs_host_node_exporter_from_monitoring" {
  security_group_id = aws_security_group.ecs_host.id
  description       = "Allow node-exporter scrape from monitoring"

  ip_protocol                  = "tcp"
  from_port                    = 9100
  to_port                      = 9100
  referenced_security_group_id = aws_security_group.monitoring.id
}

# Monitoring -> ECS Host (cAdvisor)
resource "aws_vpc_security_group_ingress_rule" "ecs_host_cadvisor_from_monitoring" {
  security_group_id = aws_security_group.ecs_host.id
  description       = "Allow cAdvisor scrape from monitoring"

  ip_protocol                  = "tcp"
  from_port                    = 8081
  to_port                      = 8081
  referenced_security_group_id = aws_security_group.monitoring.id
}

# ECS Host -> 외부 HTTPS
resource "aws_vpc_security_group_egress_rule" "ecs_host_https" {
  security_group_id = aws_security_group.ecs_host.id
  description       = "Allow HTTPS for ECS agent and image pull"

  ip_protocol = "tcp"
  from_port   = 443
  to_port     = 443
  cidr_ipv4   = "0.0.0.0/0"
}

# ---------- RDS ----------

# Backend Task -> RDS
resource "aws_vpc_security_group_ingress_rule" "rds_mysql_from_backend_task" {
  security_group_id = aws_security_group.rds.id
  description       = "Allow MySQL from backend task"

  ip_protocol                  = "tcp"
  from_port                    = 3306
  to_port                      = 3306
  referenced_security_group_id = aws_security_group.backend_task.id
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
  from_port                    = 9100
  to_port                      = 9100
  referenced_security_group_id = aws_security_group.ecs_host.id
}

# Monitoring -> ECS Host (cAdvisor)
resource "aws_vpc_security_group_egress_rule" "monitoring_to_cadvisor" {
  security_group_id = aws_security_group.monitoring.id
  description       = "Allow cAdvisor scrape to ECS host"

  ip_protocol                  = "tcp"
  from_port                    = 8081
  to_port                      = 8081
  referenced_security_group_id = aws_security_group.ecs_host.id
}

# Monitoring -> Backend Task (Actuator 메트릭 수집)
resource "aws_vpc_security_group_egress_rule" "monitoring_to_backend_task" {
  security_group_id = aws_security_group.monitoring.id
  description       = "Allow actuator metrics scrape to backend task"

  ip_protocol                  = "tcp"
  from_port                    = var.app_port
  to_port                      = var.app_port
  referenced_security_group_id = aws_security_group.backend_task.id
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
