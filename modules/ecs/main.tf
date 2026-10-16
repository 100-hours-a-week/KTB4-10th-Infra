# AWS 권장 최신 ECS 최적화 AMI (apply 시점 기준)
data "aws_ssm_parameter" "ecs_ami" {
  name = var.ami_ssm_parameter_name
}

# provider default_tags (ASG가 만드는 인스턴스와 볼륨에는 자동으로 붙지 않아서 직접 지정)
data "aws_default_tags" "current" {}

# ECS Cluster
resource "aws_ecs_cluster" "main" {
  name = "${var.name}-cluster"

  # 초기에는 비활성화 (비용)
  setting {
    name  = "containerInsights"
    value = "disabled"
  }

  tags = {
    Name = "${var.name}-cluster"
  }
}

# ECS Host Launch Template
resource "aws_launch_template" "ecs" {
  name        = "${var.name}-ecs-lt"
  description = "ECS host launch template"

  # 공개 파라미터라 민감 값 아님. aws_ssm_parameter 값은 테라폼에서 민감값으로 취급해 sensitive value로 가려지는 것 방지
  # 변경된 AMI ID를 보기 위해 insecure_value 사용
  image_id      = data.aws_ssm_parameter.ecs_ami.insecure_value
  instance_type = var.instance_type

  vpc_security_group_ids = [var.security_group_id]

  # ECS 클러스터 등록, SSM Session Manager
  iam_instance_profile {
    name = var.instance_profile_name
  }

  # 클러스터 이름 지정
  user_data = base64encode(templatefile("${path.module}/user_data.sh.tpl", {
    cluster_name = aws_ecs_cluster.main.name
  }))

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
    # bridge 모드 컨테이너는 hop이 하나 더 있어서 IMDS에 접근 못 함
    http_put_response_hop_limit = 1
  }

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = var.root_volume_size
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  tag_specifications {
    resource_type = "instance"

    tags = merge(data.aws_default_tags.current.tags, {
      Name = "${var.name}-ecs-host"
    })
  }

  tag_specifications {
    resource_type = "volume"

    tags = merge(data.aws_default_tags.current.tags, {
      Name = "${var.name}-ecs-host"
    })
  }

  tags = {
    Name = "${var.name}-ecs-lt"
  }
}

# ECS Host Auto Scaling Group (private-app subnet)
resource "aws_autoscaling_group" "ecs" {
  name                = "${var.name}-ecs-asg"
  vpc_zone_identifier = var.subnet_ids

  min_size         = var.min_size
  max_size         = var.max_size
  desired_capacity = var.desired_capacity

  health_check_type         = "EC2"
  health_check_grace_period = 300

  launch_template {
    id      = aws_launch_template.ecs.id
    version = aws_launch_template.ecs.latest_version
  }

  # 배포 파이프라인이 desired를 임시로 바꾸므로 되돌리지 않음
  lifecycle {
    ignore_changes = [desired_capacity]
  }

  tag {
    key                 = "Name"
    value               = "${var.name}-ecs-host"
    propagate_at_launch = false
  }

  # Capacity Provider 연결 시 ECS가 자동으로 붙이는 태그
  tag {
    key                 = "AmazonECSManaged"
    value               = ""
    propagate_at_launch = true
  }
}

# ECS Capacity Provider (managed scaling 비활성화, 증설은 배포 파이프라인에서)
resource "aws_ecs_capacity_provider" "ecs" {
  name = "${var.name}-ecs-cp"

  auto_scaling_group_provider {
    auto_scaling_group_arn         = aws_autoscaling_group.ecs.arn
    managed_termination_protection = "DISABLED"

    managed_scaling {
      status = "DISABLED"
    }
  }

  tags = {
    Name = "${var.name}-ecs-cp"
  }
}

resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name       = aws_ecs_cluster.main.name
  capacity_providers = [aws_ecs_capacity_provider.ecs.name]

  default_capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.ecs.name
    weight            = 1
    base              = 0
  }
}
