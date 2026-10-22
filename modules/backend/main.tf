data "aws_region" "current" {}

# ---------- 비밀 값 저장소 (값은 콘솔/CLI로 직접 입력) ----------

# Backend 비밀 환경 변수 (Parameter Store SecureString)
resource "aws_ssm_parameter" "secrets" {
  for_each = toset(var.secret_names)

  name        = "/${var.name}/backend/${each.key}"
  description = "Backend secret environment variable ${each.key}"
  type        = "SecureString"

  value = "CHANGE_ME"

  lifecycle {
    ignore_changes = [value]
  }

  tags = {
    Name = "/${var.name}/backend/${each.key}"
  }
}

# ---------- 로그 ----------

resource "aws_cloudwatch_log_group" "backend" {
  name              = "/${var.name}/backend"
  retention_in_days = var.log_retention_days

  tags = {
    Name = "/${var.name}/backend"
  }
}

# ---------- Task Definition ----------

resource "aws_ecs_task_definition" "backend" {
  family                   = "${var.name}-backend"
  network_mode             = "bridge"
  requires_compatibilities = ["EC2"]

  # 이미지 다운로드, 비밀 값 조회, 로그 전송
  execution_role_arn = var.execution_role_arn
  # 애플리케이션의 AWS API 호출 (S3)
  task_role_arn = var.task_role_arn

  container_definitions = jsonencode([
    {
      name      = "backend"
      image     = var.image
      essential = true

      # AWS가 저장 시 빈 값으로 채우는 항목. 코드에 없으면 매 plan마다 교체로 표시됨
      mountPoints    = []
      volumesFrom    = []
      systemControls = []

      # 넘으면 컨테이너가 강제 종료되는 상한 (서버당 1개 배치는 distinctInstance가 보장)
      memory = var.memory

      repositoryCredentials = {
        credentialsParameter = var.ghcr_secret_arn
      }

      # 호스트 포트 고정 (서버당 Task 1개)
      portMappings = [
        { containerPort = var.app_port, hostPort = var.app_port, protocol = "tcp" },
        { containerPort = var.management_port, hostPort = var.management_port, protocol = "tcp" },
      ]

      environment = [for k, v in var.environment : { name = k, value = v }]

      secrets = concat(
        [for n in var.secret_names : { name = n, valueFrom = aws_ssm_parameter.secrets[n].arn }],
        [for k, v in var.external_secrets : { name = k, valueFrom = v }],
      )

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.backend.name
          awslogs-region        = data.aws_region.current.region
          awslogs-stream-prefix = "backend"
        }
      }
    }
  ])

  tags = {
    Name = "${var.name}-backend"
  }
}

# ---------- Service ----------

resource "aws_ecs_service" "backend" {
  name            = "${var.name}-backend"
  cluster         = var.cluster_arn
  task_definition = aws_ecs_task_definition.backend.arn
  desired_count   = var.desired_count

  capacity_provider_strategy {
    capacity_provider = var.capacity_provider_name
    weight            = 1
    base              = 0
  }

  # 서버당 1개, AZ 분산
  placement_constraints {
    type = "distinctInstance"
  }

  ordered_placement_strategy {
    type  = "spread"
    field = "attribute:ecs.availability-zone"
  }

  # ALB Target Group 등록 (ECS가 Task의 EC2:8080을 자동 등록·해제)
  dynamic "load_balancer" {
    for_each = var.target_group_arn == null ? [] : [var.target_group_arn]

    content {
      target_group_arn = load_balancer.value
      container_name   = "backend"
      container_port   = var.app_port
    }
  }

  # Spring Boot 기동(약 16초) 중 헬스 체크 실패로 Task가 교체되지 않도록 유예
  health_check_grace_period_seconds = var.target_group_arn == null ? null : 90

  # 고정 포트라 같은 서버에 새 Task를 같이 띄울 수 없음
  # ALB와 블루/그린 도입 전까지는 1개씩 교체
  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent         = 100

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  enable_ecs_managed_tags = true
  propagate_tags          = "SERVICE"

  # 이미지는 Backend repo CD가 새 리비전을 등록해 배포하므로 되돌리지 않음
  lifecycle {
    ignore_changes = [task_definition]
  }

  tags = {
    Name = "${var.name}-backend"
  }
}
