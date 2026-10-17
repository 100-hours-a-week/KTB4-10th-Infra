# ---------- ACM 인증서 (ALB와 같은 리전) ----------

# CloudFront용 인증서는 us-east-1에 있어 ALB(서울)에서 쓸 수 없음
resource "aws_acm_certificate" "main" {
  domain_name               = var.domain_name
  subject_alternative_names = var.subject_alternative_names

  validation_method = "DNS"

  # 교체 시 새 인증서를 먼저 만들고 기존 것을 삭제 (Listener가 사용 중)
  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "${var.name}-cert"
  }
}

# DNS 검증 완료(ISSUED)까지 대기
# 같은 계정·같은 도메인의 검증 CNAME은 리전과 관계없이 같아서,
# Route 53에 이미 있는 us-east-1 인증서용 레코드로 검증된다. 레코드는 Terraform이 관리하지 않음
resource "aws_acm_certificate_validation" "main" {
  certificate_arn         = aws_acm_certificate.main.arn
  validation_record_fqdns = distinct([for o in aws_acm_certificate.main.domain_validation_options : o.resource_record_name])

  # 레코드가 없거나 다르면 기본 75분을 기다리므로 빨리 실패하도록 단축
  timeouts {
    create = "15m"
  }
}

# ---------- ALB ----------

resource "aws_lb" "main" {
  name               = "${var.name}-alb"
  load_balancer_type = "application"
  internal           = false
  subnets            = var.public_subnet_ids
  security_groups    = [var.security_group_id]

  # 잘못된 형식의 헤더를 가진 요청은 Backend로 넘기지 않음
  drop_invalid_header_fields = true

  # SSE 하트비트(15초)보다 길게
  idle_timeout = 60

  enable_deletion_protection = var.deletion_protection

  tags = {
    Name = "${var.name}-alb"
  }
}

# Backend Target Group (bridge 모드라 instance 타입, 트래픽은 8080, 헬스 체크는 관리 포트 8081)
resource "aws_lb_target_group" "backend" {
  name        = "${var.name}-backend-tg"
  vpc_id      = var.vpc_id
  target_type = "instance"
  protocol    = "HTTP"
  port        = var.app_port

  # 교체 전 기존 요청을 마무리할 시간
  deregistration_delay = 30

  health_check {
    protocol            = "HTTP"
    port                = tostring(var.management_port)
    path                = "/actuator/health"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = {
    Name = "${var.name}-backend-tg"
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.main.arn
  protocol          = "HTTPS"
  port              = 443
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate_validation.main.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend.arn
  }

  tags = {
    Name = "${var.name}-alb-https"
  }
}

# ---------- 테스트용 접근 (CloudFront 연결 전 직접 확인) ----------

# 비워 두면 생성하지 않음. 테스트 후 반드시 비울 것
resource "aws_vpc_security_group_ingress_rule" "alb_https_test" {
  for_each = toset(var.test_allowed_cidrs)

  security_group_id = var.security_group_id
  description       = "Temporary HTTPS test access to ALB"

  ip_protocol = "tcp"
  from_port   = 443
  to_port     = 443
  cidr_ipv4   = each.value
}
