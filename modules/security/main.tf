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

# NAT/Bastion SG (AZ별 인스턴스가 같이 사용)
resource "aws_security_group" "nat_bastion" {
  name        = "${var.name}-nat-bastion-sg"
  description = "NAT and bastion security group"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.name}-nat-bastion-sg"
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

# Bastion -> ECS Host
resource "aws_vpc_security_group_ingress_rule" "ecs_host_ssh_from_bastion" {
  security_group_id = aws_security_group.ecs_host.id
  description       = "Allow SSH from bastion"

  ip_protocol                  = "tcp"
  from_port                    = 22
  to_port                      = 22
  referenced_security_group_id = aws_security_group.nat_bastion.id
}

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

# Bastion -> RDS (운영자 SSH 터널)
resource "aws_vpc_security_group_ingress_rule" "rds_mysql_from_bastion" {
  security_group_id = aws_security_group.rds.id
  description       = "Allow MySQL from bastion SSH tunnel"

  ip_protocol                  = "tcp"
  from_port                    = 3306
  to_port                      = 3306
  referenced_security_group_id = aws_security_group.nat_bastion.id
}

# ---------- Monitoring ----------

# Bastion -> Monitoring (SSH)
resource "aws_vpc_security_group_ingress_rule" "monitoring_ssh_from_bastion" {
  security_group_id = aws_security_group.monitoring.id
  description       = "Allow SSH from bastion"

  ip_protocol                  = "tcp"
  from_port                    = 22
  to_port                      = 22
  referenced_security_group_id = aws_security_group.nat_bastion.id
}

# Bastion -> Monitoring (Grafana SSH 터널)
resource "aws_vpc_security_group_ingress_rule" "monitoring_grafana_from_bastion" {
  security_group_id = aws_security_group.monitoring.id
  description       = "Allow Grafana from bastion SSH tunnel"

  ip_protocol                  = "tcp"
  from_port                    = 3000
  to_port                      = 3000
  referenced_security_group_id = aws_security_group.nat_bastion.id
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

# ---------- NAT/Bastion ----------

# 운영자 -> Bastion
resource "aws_vpc_security_group_ingress_rule" "nat_bastion_ssh_from_operator" {
  for_each = toset(var.operator_cidrs)

  security_group_id = aws_security_group.nat_bastion.id
  description       = "Allow SSH from operator"

  ip_protocol = "tcp"
  from_port   = 22
  to_port     = 22
  cidr_ipv4   = each.value
}

# Private app subnet -> NAT
resource "aws_vpc_security_group_ingress_rule" "nat_bastion_https_from_private_app" {
  for_each = toset(var.private_app_subnet_cidrs)

  security_group_id = aws_security_group.nat_bastion.id
  description       = "Allow HTTPS from private app subnet for NAT"

  ip_protocol = "tcp"
  from_port   = 443
  to_port     = 443
  cidr_ipv4   = each.value
}

# Bastion -> ECS Host
resource "aws_vpc_security_group_egress_rule" "nat_bastion_ssh_to_ecs_host" {
  security_group_id = aws_security_group.nat_bastion.id
  description       = "Allow SSH to ECS host"

  ip_protocol                  = "tcp"
  from_port                    = 22
  to_port                      = 22
  referenced_security_group_id = aws_security_group.ecs_host.id
}

# Bastion -> Monitoring (SSH)
resource "aws_vpc_security_group_egress_rule" "nat_bastion_ssh_to_monitoring" {
  security_group_id = aws_security_group.nat_bastion.id
  description       = "Allow SSH to monitoring"

  ip_protocol                  = "tcp"
  from_port                    = 22
  to_port                      = 22
  referenced_security_group_id = aws_security_group.monitoring.id
}

# Bastion -> Monitoring (Grafana SSH 터널)
resource "aws_vpc_security_group_egress_rule" "nat_bastion_grafana_to_monitoring" {
  security_group_id = aws_security_group.nat_bastion.id
  description       = "Allow Grafana SSH tunnel to monitoring"

  ip_protocol                  = "tcp"
  from_port                    = 3000
  to_port                      = 3000
  referenced_security_group_id = aws_security_group.monitoring.id
}

# Bastion -> RDS (운영자 SSH 터널)
resource "aws_vpc_security_group_egress_rule" "nat_bastion_mysql_to_rds" {
  security_group_id = aws_security_group.nat_bastion.id
  description       = "Allow MySQL SSH tunnel to RDS"

  ip_protocol                  = "tcp"
  from_port                    = 3306
  to_port                      = 3306
  referenced_security_group_id = aws_security_group.rds.id
}

# NAT -> 인터넷
resource "aws_vpc_security_group_egress_rule" "nat_bastion_https" {
  security_group_id = aws_security_group.nat_bastion.id
  description       = "Allow HTTPS to internet for NAT"

  ip_protocol = "tcp"
  from_port   = 443
  to_port     = 443
  cidr_ipv4   = "0.0.0.0/0"
}
