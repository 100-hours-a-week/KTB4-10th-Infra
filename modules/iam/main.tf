data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition
  region     = data.aws_region.current.region

  github_oidc_url = "token.actions.githubusercontent.com"
}

data "aws_iam_openid_connect_provider" "github" {
  url = "https://${local.github_oidc_url}"
}

# ---------- 신뢰 정책 ----------

# EC2 인스턴스가 Assume
data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

# ECS Task가 Assume 
data "aws_iam_policy_document" "ecs_tasks_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

# ---------- ECS Host ----------

# ECS 인스턴스 역할
# ECS 클러스터에 EC2 등록, ECS 에이전트 실행
resource "aws_iam_role" "ecs_instance" {
  name               = "${var.name}-ecs-instance-role"
  description        = "ECS container instance role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json

  tags = {
    Name = "${var.name}-ecs-instance-role"
  }
}

# ECS 에이전트 등록, CloudWatch Logs 쓰기 (AWS 관리형 정책)
resource "aws_iam_role_policy_attachment" "ecs_instance" {
  role       = aws_iam_role.ecs_instance.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_instance_profile" "ecs_instance" {
  name = "${var.name}-ecs-instance-profile"
  role = aws_iam_role.ecs_instance.name

  tags = {
    Name = "${var.name}-ecs-instance-profile"
  }
}

# ---------- Backend Task ----------

# 태스크 실행 역할 (태스크 시작 시 ECS가 사용)
resource "aws_iam_role" "task_execution" {
  name               = "${var.name}-task-execution-role"
  description        = "ECS task execution role"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json

  tags = {
    Name = "${var.name}-task-execution-role"
  }
}

# GHCR 자격 증명 등 "${var.name}/" 아래의 시크릿 읽기
data "aws_iam_policy_document" "task_execution" {
  statement {
    sid       = "ReadSecrets"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = ["arn:${local.partition}:secretsmanager:${local.region}:${local.account_id}:secret:${var.name}/*"]
  }
}

resource "aws_iam_role_policy" "task_execution" {
  name   = "${var.name}-task-execution-policy"
  role   = aws_iam_role.task_execution.id
  policy = data.aws_iam_policy_document.task_execution.json
}

resource "aws_iam_role_policy_attachment" "task_execution" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# 태스크 역할 (애플리케이션이 사용, 권한은 필요할 때 추가)
resource "aws_iam_role" "task" {
  name               = "${var.name}-task-role"
  description        = "Backend task role"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json

  tags = {
    Name = "${var.name}-task-role"
  }
}

# ---------- Monitoring ----------

# Monitoring 인스턴스 역할
resource "aws_iam_role" "monitoring" {
  name               = "${var.name}-monitoring-role"
  description        = "Monitoring instance role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json

  tags = {
    Name = "${var.name}-monitoring-role"
  }
}

# Prometheus 스크랩 대상 조회 (읽기 전용)
data "aws_iam_policy_document" "monitoring" {
  statement {
    sid = "DiscoverScrapeTargets"
    actions = [
      "ec2:DescribeAvailabilityZones",
      "ec2:DescribeInstances",
      "ecs:DescribeClusters",
      "ecs:DescribeContainerInstances",
      "ecs:DescribeServices",
      "ecs:DescribeTaskDefinition",
      "ecs:DescribeTasks",
      "ecs:ListClusters",
      "ecs:ListServices",
      "ecs:ListTasks",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "monitoring" {
  name   = "${var.name}-monitoring-policy"
  role   = aws_iam_role.monitoring.id
  policy = data.aws_iam_policy_document.monitoring.json
}

resource "aws_iam_instance_profile" "monitoring" {
  name = "${var.name}-monitoring-profile"
  role = aws_iam_role.monitoring.name

  tags = {
    Name = "${var.name}-monitoring-profile"
  }
}

# ---------- GitHub Actions: Backend ----------

# 지정한 저장소/브랜치의 워크플로만 Assume
data "aws_iam_policy_document" "github_backend_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.github_oidc_url}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.github_oidc_url}:sub"
      values   = var.github_backend_subjects
    }
  }
}

# GitHub Actions 배포 역할
resource "aws_iam_role" "github_backend_deploy" {
  name               = "${var.name}-backend-deploy-role"
  description        = "GitHub Actions ECS deploy role"
  assume_role_policy = data.aws_iam_policy_document.github_backend_assume.json

  tags = {
    Name = "${var.name}-backend-deploy-role"
  }
}

# ECS 배포 권한
data "aws_iam_policy_document" "github_backend_deploy" {
  statement {
    sid = "RegisterTaskDefinition"
    actions = [
      "ecs:DescribeTaskDefinition",
      "ecs:RegisterTaskDefinition",
    ]
    resources = ["*"]
  }

  statement {
    sid = "UpdateService"
    actions = [
      "ecs:DescribeServices",
      "ecs:UpdateService",
    ]
    resources = ["arn:${local.partition}:ecs:${local.region}:${local.account_id}:service/${var.name}-*/*"]
  }

  # 태스크 정의에 넣을 역할만 ECS Task에 전달 가능
  statement {
    sid     = "PassTaskRoles"
    actions = ["iam:PassRole"]
    resources = [
      aws_iam_role.task_execution.arn,
      aws_iam_role.task.arn,
    ]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# 백엔드 Role에 배포 권한 연결
resource "aws_iam_role_policy" "github_backend_deploy" {
  name   = "${var.name}-backend-deploy-policy"
  role   = aws_iam_role.github_backend_deploy.id
  policy = data.aws_iam_policy_document.github_backend_deploy.json
}

# ---------- GitHub Actions: Frontend ----------

# 프론트엔드 GitHub Actions만 Assume 가능
data "aws_iam_policy_document" "github_frontend_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.github_oidc_url}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.github_oidc_url}:sub"
      values   = var.github_frontend_subjects
    }
  }
}

# 프론트엔드 배포 Role
resource "aws_iam_role" "github_frontend_deploy" {
  name               = "${var.name}-frontend-deploy-role"
  description        = "GitHub Actions frontend deploy role"
  assume_role_policy = data.aws_iam_policy_document.github_frontend_assume.json

  tags = {
    Name = "${var.name}-frontend-deploy-role"
  }
}

# S3 배포 및 CloudFront 캐시 무효화 권한
data "aws_iam_policy_document" "github_frontend_deploy" {

  # S3 버킷 조회
  statement {
    sid     = "ListFrontendBucket"
    actions = ["s3:ListBucket"]
    resources = [
      "arn:${local.partition}:s3:::${var.frontend_bucket_name}"
    ]
  }

  # 정적 파일 업로드 및 삭제
  statement {
    sid = "DeployFrontendFiles"
    actions = [
      "s3:PutObject",
      "s3:DeleteObject"
    ]
    resources = [
      "arn:${local.partition}:s3:::${var.frontend_bucket_name}/*"
    ]
  }

  # CloudFront 캐시 무효화
  statement {
    sid = "InvalidateCloudFront"
    actions = [
      "cloudfront:CreateInvalidation",
      "cloudfront:GetInvalidation"
    ]
    resources = [
      "arn:${local.partition}:cloudfront::${local.account_id}:distribution/${var.frontend_cloudfront_distribution_id}"
    ]
  }
}

# 프론트엔드 Role에 권한 연결
resource "aws_iam_role_policy" "github_frontend_deploy" {
  name   = "${var.name}-frontend-deploy-policy"
  role   = aws_iam_role.github_frontend_deploy.id
  policy = data.aws_iam_policy_document.github_frontend_deploy.json
}
