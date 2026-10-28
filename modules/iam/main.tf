data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition
  region     = data.aws_region.current.region

  github_oidc_url = "token.actions.githubusercontent.com"

  # subject를 비우면 GitHub 배포 역할을 만들지 않음 (staging 등)
  create_backend_deploy  = length(var.github_backend_subjects) > 0
  create_ai_deploy       = length(var.github_ai_subjects) > 0
  create_frontend_deploy = length(var.github_frontend_subjects) > 0
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

# Session Manager 접속
resource "aws_iam_role_policy_attachment" "ecs_instance_ssm" {
  role       = aws_iam_role.ecs_instance.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
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

  # 컨테이너 환경 변수로 주입할 시크릿 (기본 KMS 키 aws/ssm으로 암호화)
  statement {
    sid       = "ReadParameters"
    actions   = ["ssm:GetParameters"]
    resources = ["arn:${local.partition}:ssm:${local.region}:${local.account_id}:parameter/${var.name}/*"]
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

# Backend 파일 저장소 (V1 kgb-be-ec2-role의 s3access와 같은 범위, 버킷 미지정 시 생략)
data "aws_iam_policy_document" "task" {
  count = var.backend_storage_bucket_name == null ? 0 : 1

  statement {
    sid       = "ListStorageBucket"
    actions   = ["s3:ListBucket"]
    resources = ["arn:${local.partition}:s3:::${var.backend_storage_bucket_name}"]
  }

  statement {
    sid = "ReadWriteStorageObjects"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = ["arn:${local.partition}:s3:::${var.backend_storage_bucket_name}/*"]
  }
}

resource "aws_iam_role_policy" "task" {
  count = var.backend_storage_bucket_name == null ? 0 : 1

  name   = "${var.name}-task-policy"
  role   = aws_iam_role.task.id
  policy = data.aws_iam_policy_document.task[0].json
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

  # Grafana 관리자, mysqld-exporter 비밀번호 (user_data에서 조회)
  statement {
    sid       = "ReadMonitoringSecrets"
    actions   = ["ssm:GetParameter", "ssm:GetParameters"]
    resources = ["arn:${local.partition}:ssm:${local.region}:${local.account_id}:parameter/${var.name}/monitoring/*"]
  }
}

resource "aws_iam_role_policy" "monitoring" {
  name   = "${var.name}-monitoring-policy"
  role   = aws_iam_role.monitoring.id
  policy = data.aws_iam_policy_document.monitoring.json
}

# Session Manager 접속
resource "aws_iam_role_policy_attachment" "monitoring_ssm" {
  role       = aws_iam_role.monitoring.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "monitoring" {
  name = "${var.name}-monitoring-profile"
  role = aws_iam_role.monitoring.name

  tags = {
    Name = "${var.name}-monitoring-profile"
  }
}

# ---------- NAT ----------

# NAT 인스턴스 역할
resource "aws_iam_role" "nat" {
  name               = "${var.name}-nat-role"
  description        = "NAT instance role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json

  tags = {
    Name = "${var.name}-nat-role"
  }
}

# Session Manager 접속
resource "aws_iam_role_policy_attachment" "nat_ssm" {
  role       = aws_iam_role.nat.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "nat" {
  name = "${var.name}-nat-profile"
  role = aws_iam_role.nat.name

  tags = {
    Name = "${var.name}-nat-profile"
  }
}

# ---------- 개발자 접근 ----------

# NAT 인스턴스를 통한 SSM 포트 포워딩만 허용 (셸 접속 불가)
data "aws_iam_policy_document" "developer_port_forward" {
  statement {
    sid     = "StartPortForwarding"
    actions = ["ssm:StartSession"]

    resources = concat(
      [for id in var.nat_instance_ids : "arn:${local.partition}:ec2:${local.region}:${local.account_id}:instance/${id}"],
      ["arn:${local.partition}:ssm:${local.region}::document/AWS-StartPortForwardingSessionToRemoteHost"]
    )

    # 문서를 지정하지 않은 기본 셸 세션까지 문서 권한을 검사
    condition {
      test     = "BoolIfExists"
      variable = "ssm:SessionDocumentAccessCheck"
      values   = ["true"]
    }
  }

  # 본인이 연 세션만 연결/종료/재개
  statement {
    sid       = "ManageOwnSession"
    actions   = ["ssmmessages:OpenDataChannel", "ssm:TerminateSession", "ssm:ResumeSession"]
    resources = ["arn:${local.partition}:ssm:*:*:session/$${aws:userid}-*"]
  }
}

# 개발자 사용자/그룹에 연결해서 사용
resource "aws_iam_policy" "developer_port_forward" {
  name        = "${var.name}-developer-port-forward-policy"
  description = "Allow SSM port forwarding through NAT instance"
  policy      = data.aws_iam_policy_document.developer_port_forward.json

  tags = {
    Name = "${var.name}-developer-port-forward-policy"
  }
}

# ---------- GitHub Actions: Backend ----------

# 지정한 저장소/브랜치의 워크플로만 Assume
data "aws_iam_policy_document" "github_backend_assume" {
  count = local.create_backend_deploy ? 1 : 0

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
  count = local.create_backend_deploy ? 1 : 0

  name               = "${var.name}-backend-deploy-role"
  description        = "GitHub Actions ECS deploy role"
  assume_role_policy = data.aws_iam_policy_document.github_backend_assume[0].json

  tags = {
    Name = "${var.name}-backend-deploy-role"
  }
}

# ECS 배포 권한
data "aws_iam_policy_document" "github_backend_deploy" {
  count = local.create_backend_deploy ? 1 : 0

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
    resources = ["arn:${local.partition}:ecs:${local.region}:${local.account_id}:service/${var.name}-cluster/${var.name}-backend"]
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
  count = local.create_backend_deploy ? 1 : 0

  name   = "${var.name}-backend-deploy-policy"
  role   = aws_iam_role.github_backend_deploy[0].id
  policy = data.aws_iam_policy_document.github_backend_deploy[0].json
}

# ---------- GitHub Actions: AI ----------

# 지정한 저장소/브랜치의 워크플로만 Assume
data "aws_iam_policy_document" "github_ai_assume" {
  count = local.create_ai_deploy ? 1 : 0

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
      values   = var.github_ai_subjects
    }
  }
}

# GitHub Actions 배포 역할
resource "aws_iam_role" "github_ai_deploy" {
  count = local.create_ai_deploy ? 1 : 0

  name               = "${var.name}-ai-deploy-role"
  description        = "GitHub Actions AI ECS deploy role"
  assume_role_policy = data.aws_iam_policy_document.github_ai_assume[0].json

  tags = {
    Name = "${var.name}-ai-deploy-role"
  }
}

# ECS 배포 권한
data "aws_iam_policy_document" "github_ai_deploy" {
  count = local.create_ai_deploy ? 1 : 0

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
    resources = ["arn:${local.partition}:ecs:${local.region}:${local.account_id}:service/${var.name}-cluster/${var.name}-ai"]
  }

  # AI Task는 Task Role 없이 실행 역할만 사용
  statement {
    sid       = "PassTaskRoles"
    actions   = ["iam:PassRole"]
    resources = [aws_iam_role.task_execution.arn]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# AI Role에 배포 권한 연결
resource "aws_iam_role_policy" "github_ai_deploy" {
  count = local.create_ai_deploy ? 1 : 0

  name   = "${var.name}-ai-deploy-policy"
  role   = aws_iam_role.github_ai_deploy[0].id
  policy = data.aws_iam_policy_document.github_ai_deploy[0].json
}

# ---------- GitHub Actions: Frontend ----------

# 프론트엔드 GitHub Actions만 Assume 가능
data "aws_iam_policy_document" "github_frontend_assume" {
  count = local.create_frontend_deploy ? 1 : 0

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
  count = local.create_frontend_deploy ? 1 : 0

  name               = "${var.name}-frontend-deploy-role"
  description        = "GitHub Actions frontend deploy role"
  assume_role_policy = data.aws_iam_policy_document.github_frontend_assume[0].json

  tags = {
    Name = "${var.name}-frontend-deploy-role"
  }
}

# S3 배포 및 CloudFront 캐시 무효화 권한
data "aws_iam_policy_document" "github_frontend_deploy" {
  count = local.create_frontend_deploy ? 1 : 0

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
  count = local.create_frontend_deploy ? 1 : 0

  name   = "${var.name}-frontend-deploy-policy"
  role   = aws_iam_role.github_frontend_deploy[0].id
  policy = data.aws_iam_policy_document.github_frontend_deploy[0].json
}
