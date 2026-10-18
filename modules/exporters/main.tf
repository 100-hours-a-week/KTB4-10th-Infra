data "aws_region" "current" {}

# ---------- 로그 ----------

resource "aws_cloudwatch_log_group" "exporters" {
  name              = "/${var.name}/exporters"
  retention_in_days = var.log_retention_days

  tags = {
    Name = "/${var.name}/exporters"
  }
}

# ---------- node-exporter (서버 지표) ----------

resource "aws_ecs_task_definition" "node_exporter" {
  family = "${var.name}-node-exporter"
  # 서버의 네트워크 인터페이스 지표를 그대로 보기 위해 host 모드
  network_mode             = "host"
  pid_mode                 = "host"
  requires_compatibilities = ["EC2"]

  # 로그 전송
  execution_role_arn = var.execution_role_arn

  volume {
    name      = "proc"
    host_path = "/proc"
  }

  volume {
    name      = "sys"
    host_path = "/sys"
  }

  volume {
    name      = "root"
    host_path = "/"
  }

  container_definitions = jsonencode([
    {
      name      = "node-exporter"
      image     = var.node_exporter_image
      essential = true

      volumesFrom    = []
      systemControls = []

      memory = var.node_exporter_memory

      command = [
        "--path.procfs=/host/proc",
        "--path.sysfs=/host/sys",
        "--path.rootfs=/host/root",
        "--web.listen-address=:${var.node_exporter_port}",
      ]

      mountPoints = [
        { sourceVolume = "proc", containerPath = "/host/proc", readOnly = true },
        { sourceVolume = "sys", containerPath = "/host/sys", readOnly = true },
        { sourceVolume = "root", containerPath = "/host/root", readOnly = true },
      ]

      portMappings = [
        { containerPort = var.node_exporter_port, hostPort = var.node_exporter_port, protocol = "tcp" },
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.exporters.name
          awslogs-region        = data.aws_region.current.region
          awslogs-stream-prefix = "node-exporter"
        }
      }
    }
  ])

  tags = {
    Name = "${var.name}-node-exporter"
  }
}

# ---------- cAdvisor (컨테이너 지표) ----------

resource "aws_ecs_task_definition" "cadvisor" {
  family                   = "${var.name}-cadvisor"
  network_mode             = "bridge"
  requires_compatibilities = ["EC2"]

  execution_role_arn = var.execution_role_arn

  volume {
    name      = "rootfs"
    host_path = "/"
  }

  volume {
    name      = "var_run"
    host_path = "/var/run"
  }

  volume {
    name      = "sys"
    host_path = "/sys"
  }

  volume {
    name      = "docker"
    host_path = "/var/lib/docker"
  }

  volume {
    name      = "dev_disk"
    host_path = "/dev/disk"
  }

  container_definitions = jsonencode([
    {
      name      = "cadvisor"
      image     = var.cadvisor_image
      essential = true

      volumesFrom    = []
      systemControls = []

      memory = var.cadvisor_memory

      # 호스트의 cgroup과 Docker 정보를 읽기 위해 필요
      privileged = true

      command = [
        "--docker_only=true",
        "--housekeeping_interval=30s",
      ]

      mountPoints = [
        { sourceVolume = "rootfs", containerPath = "/rootfs", readOnly = true },
        { sourceVolume = "var_run", containerPath = "/var/run", readOnly = true },
        { sourceVolume = "sys", containerPath = "/sys", readOnly = true },
        { sourceVolume = "docker", containerPath = "/var/lib/docker", readOnly = true },
        { sourceVolume = "dev_disk", containerPath = "/dev/disk", readOnly = true },
      ]

      # 컨테이너 8080은 Backend와 겹치지 않게 호스트에서는 별도 포트로 노출
      portMappings = [
        { containerPort = 8080, hostPort = var.cadvisor_port, protocol = "tcp" },
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.exporters.name
          awslogs-region        = data.aws_region.current.region
          awslogs-stream-prefix = "cadvisor"
        }
      }
    }
  ])

  tags = {
    Name = "${var.name}-cadvisor"
  }
}

# ---------- Service ----------

# DAEMON: 클러스터의 모든 서버(ECS Host, AI 서버)에 1개씩 배치
# 서버가 교체되거나 늘어나면 ECS가 새 서버에도 자동으로 띄움
resource "aws_ecs_service" "node_exporter" {
  name                = "${var.name}-node-exporter"
  cluster             = var.cluster_arn
  task_definition     = aws_ecs_task_definition.node_exporter.arn
  scheduling_strategy = "DAEMON"

  # DAEMON은 Capacity Provider를 쓸 수 없음
  launch_type = "EC2"

  enable_ecs_managed_tags = true
  propagate_tags          = "SERVICE"

  tags = {
    Name = "${var.name}-node-exporter"
  }
}

resource "aws_ecs_service" "cadvisor" {
  name                = "${var.name}-cadvisor"
  cluster             = var.cluster_arn
  task_definition     = aws_ecs_task_definition.cadvisor.arn
  scheduling_strategy = "DAEMON"

  launch_type = "EC2"

  enable_ecs_managed_tags = true
  propagate_tags          = "SERVICE"

  tags = {
    Name = "${var.name}-cadvisor"
  }
}
