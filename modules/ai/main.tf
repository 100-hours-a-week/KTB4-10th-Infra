data "aws_region" "current" {}

# ---------- 비밀 값 저장소 (값은 콘솔/CLI로 직접 입력) ----------

# AI 비밀 환경 변수 (Parameter Store SecureString)
resource "aws_ssm_parameter" "secrets" {
  for_each = toset(var.secret_names)

  name        = "/${var.name}/ai/${each.key}"
  description = "AI secret environment variable ${each.key}"
  type        = "SecureString"

  value = "CHANGE_ME"

  lifecycle {
    ignore_changes = [value]
  }

  tags = {
    Name = "/${var.name}/ai/${each.key}"
  }
}

# ---------- AI 전용 EC2 (IP 고정) ----------

# ASG 대신 단일 인스턴스로 두어 사설 IP를 고정. Backend는 이 IP로 AI를 호출
resource "aws_instance" "ai" {
  ami           = var.ami_id
  instance_type = var.instance_type

  subnet_id              = var.subnet_id
  private_ip             = var.private_ip
  vpc_security_group_ids = [var.security_group_id]

  # ECS 클러스터 등록, SSM Session Manager
  iam_instance_profile = var.instance_profile_name

  user_data = templatefile("${path.module}/user_data.sh.tpl", {
    cluster_name = var.cluster_name
  })
  user_data_replace_on_change = true

  metadata_options {
    http_tokens = "required"
    # bridge 모드 컨테이너는 hop이 하나 더 있어서 IMDS에 접근 못 함
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_size = var.root_volume_size
    volume_type = "gp3"
    encrypted   = true
  }

  tags = {
    Name = "${var.name}-ai"
  }
}

# ---------- 로그 ----------

resource "aws_cloudwatch_log_group" "ai" {
  name              = "/${var.name}/ai"
  retention_in_days = var.log_retention_days

  tags = {
    Name = "/${var.name}/ai"
  }
}

# ---------- Task Definition ----------

resource "aws_ecs_task_definition" "ai" {
  family                   = "${var.name}-ai"
  network_mode             = "bridge"
  requires_compatibilities = ["EC2"]

  # 이미지 다운로드(GHCR 인증), 로그 전송
  execution_role_arn = var.execution_role_arn

  container_definitions = jsonencode([
    {
      name      = "ai"
      image     = var.image
      essential = true

      mountPoints    = []
      volumesFrom    = []
      systemControls = []

      # 넘으면 컨테이너가 강제 종료되는 상한
      memory = var.memory

      # 생성 작업(p95 약 58초)을 마무리할 시간. 기본 30초면 배포 중 작업이 잘림
      stopTimeout = var.stop_timeout

      repositoryCredentials = {
        credentialsParameter = var.ghcr_secret_arn
      }

      # IP와 포트를 모두 고정 
      portMappings = [
        { containerPort = var.port, hostPort = var.port, protocol = "tcp" },
      ]

      environment = [for k, v in var.environment : { name = k, value = v }]

      secrets = [for n in var.secret_names : { name = n, valueFrom = aws_ssm_parameter.secrets[n].arn }]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.ai.name
          awslogs-region        = data.aws_region.current.region
          awslogs-stream-prefix = "ai"
        }
      }
    }
  ])

  tags = {
    Name = "${var.name}-ai"
  }
}

# ---------- Service ----------

resource "aws_ecs_service" "ai" {
  name            = "${var.name}-ai"
  cluster         = var.cluster_arn
  task_definition = aws_ecs_task_definition.ai.arn
  desired_count   = var.desired_count

  # Backend의 Capacity Provider(ASG 서버)와 분리. AI 전용 EC2에만 배치
  launch_type = "EC2"

  placement_constraints {
    type       = "memberOf"
    expression = "attribute:workload == ai"
  }

  # AI 서버 1대, 고정 포트라 새 Task를 같이 띄울 수 없음
  # 작업 큐를 메모리에 두므로 Task는 1개만 유지 (배포 중 잠깐 중단)
  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  enable_ecs_managed_tags = true
  propagate_tags          = "SERVICE"

  # 이미지는 AI repo CD가 새 리비전을 등록해 배포하므로 되돌리지 않음
  # Terraform에서 바꾼 설정(환경 변수 등)은 새 리비전만 만들고, 서비스 반영은 CD 실행 또는 수동 update-service
  lifecycle {
    ignore_changes = [task_definition]
  }

  tags = {
    Name = "${var.name}-ai"
  }
}
