data "aws_region" "current" {}

# ---------- 비밀 값 저장소 (값은 콘솔/CLI로 직접 입력) ----------

resource "aws_ssm_parameter" "secrets" {
  for_each = toset(["GRAFANA_ADMIN_PASSWORD", "MYSQL_EXPORTER_PASSWORD"])

  name        = "/${var.name}/monitoring/${each.key}"
  description = "Monitoring secret ${each.key}"
  type        = "SecureString"

  # 값을 입력하기 전까지 user_data가 기다림 (CHANGE_ME로 Grafana가 초기화되지 않게)
  value = "CHANGE_ME"

  lifecycle {
    ignore_changes = [value]
  }

  tags = {
    Name = "/${var.name}/monitoring/${each.key}"
  }
}

# ---------- 설정 파일 ----------

locals {
  compose = templatefile("${path.module}/templates/docker-compose.yml.tpl", {
    prometheus_image      = var.prometheus_image
    grafana_image         = var.grafana_image
    mysqld_exporter_image = var.mysqld_exporter_image
    retention_time        = var.retention_time
    retention_size        = var.retention_size
    db_address            = "${var.db_address}:${var.db_port}"
    db_username           = var.db_username
  })

  prometheus = templatefile("${path.module}/templates/prometheus.yml.tpl", {
    region             = data.aws_region.current.region
    ecs_host_name      = var.ecs_host_name_tag
    ai_name            = var.ai_name_tag
    ai_target          = "${var.ai_private_ip}:${var.ai_port}"
    management_port    = var.management_port
    node_exporter_port = var.node_exporter_port
    cadvisor_port      = var.cadvisor_port
  })

  # files/grafana/dashboards/*.json (V1 kgb-overview.json)
  dashboard_dir = "${path.module}/files/grafana/dashboards"
  dashboards    = { for f in fileset(local.dashboard_dir, "*.json") : f => file("${local.dashboard_dir}/${f}") }
}

# ---------- Monitoring EC2 (IP 고정) ----------

resource "aws_instance" "monitoring" {
  ami           = var.ami_id
  instance_type = var.instance_type

  subnet_id              = var.subnet_id
  private_ip             = var.private_ip
  vpc_security_group_ids = [var.security_group_id]

  # Prometheus EC2 탐색, 비밀 값 조회, SSM Session Manager
  iam_instance_profile = var.instance_profile_name

  # 대시보드 JSON이 커서 16KB 제한을 넘으므로 압축해서 전달
  user_data_base64 = base64gzip(templatefile("${path.module}/templates/user_data.sh.tpl", {
    region              = data.aws_region.current.region
    compose             = local.compose
    prometheus          = local.prometheus
    grafana_datasources = file("${path.module}/files/grafana/datasources.yml")
    grafana_dashboards  = file("${path.module}/files/grafana/dashboards.yml")
    dashboards          = local.dashboards
    grafana_param       = aws_ssm_parameter.secrets["GRAFANA_ADMIN_PASSWORD"].name
    exporter_param      = aws_ssm_parameter.secrets["MYSQL_EXPORTER_PASSWORD"].name
  }))

  # user_data는 처음 설치용. 이후 설정 변경은 서버에서 직접 하고 레포에도 반영
  # (교체되면 Docker 볼륨의 지표 기록이 사라지고, 변경만 해도 서버가 중지/재시작됨)
  user_data_replace_on_change = false

  metadata_options {
    http_tokens = "required"
    # Prometheus 컨테이너(bridge)가 EC2 탐색에 인스턴스 권한을 써야 해서 hop 2
    http_put_response_hop_limit = 2
  }

  root_block_device {
    volume_size = var.root_volume_size
    volume_type = "gp3"
    encrypted   = true
  }

  lifecycle {
    ignore_changes = [user_data_base64]
  }

  tags = {
    Name = "${var.name}-monitoring"
  }
}
