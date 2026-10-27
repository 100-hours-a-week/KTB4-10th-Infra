# Valkey, 단일 노드, 전송 암호화 + 인증 토큰

# Redis SG (아웃바운드 규칙 없음)
resource "aws_security_group" "redis" {
  name        = "${var.name}-redis-sg"
  description = "Redis security group"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.name}-redis-sg"
  }
}

# 클라이언트(ECS Host) -> Redis
resource "aws_vpc_security_group_egress_rule" "client_to_redis" {
  security_group_id = var.client_security_group_id
  description       = "Allow ECS Backend to access Redis"

  ip_protocol                  = "tcp"
  from_port                    = var.port
  to_port                      = var.port
  referenced_security_group_id = aws_security_group.redis.id
}

resource "aws_vpc_security_group_ingress_rule" "redis_from_client" {
  security_group_id = aws_security_group.redis.id
  description       = "Allow Redis from ECS Backend"

  ip_protocol                  = "tcp"
  from_port                    = var.port
  to_port                      = var.port
  referenced_security_group_id = var.client_security_group_id
}

resource "aws_elasticache_subnet_group" "main" {
  name        = "${var.name}-redis-subnet-group"
  description = "Private subnets for Redis"
  subnet_ids  = var.subnet_ids

  tags = {
    Name = "${var.name}-redis-subnet-group"
  }
}

# Redis AUTH 토큰
ephemeral "aws_secretsmanager_random_password" "auth_token" {
  password_length     = 32
  exclude_punctuation = true
}

# Backend가 REDIS_PASSWORD로 주입받는 값
resource "aws_secretsmanager_secret" "auth_token" {
  name        = "${var.name}/redis/auth-token"
  description = "Redis AUTH token"

  tags = {
    Name = "${var.name}/redis/auth-token"
  }
}

# 토큰 교체 시 두 version 숫자를 같이 올림
resource "aws_secretsmanager_secret_version" "auth_token" {
  secret_id                = aws_secretsmanager_secret.auth_token.id
  secret_string_wo         = ephemeral.aws_secretsmanager_random_password.auth_token.random_password
  secret_string_wo_version = 1
}

resource "aws_elasticache_replication_group" "main" {
  replication_group_id = "${var.name}-redis"
  description          = "Redis for ${var.name}"

  engine               = "valkey"
  engine_version       = var.engine_version
  parameter_group_name = var.parameter_group_name
  node_type            = var.node_type
  port                 = var.port

  # 단일 노드 (복제본, 자동 장애 조치 없음)
  num_cache_clusters         = 1
  automatic_failover_enabled = false
  multi_az_enabled           = false

  subnet_group_name  = aws_elasticache_subnet_group.main.name
  security_group_ids = [aws_security_group.redis.id]

  # 암호화
  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  transit_encryption_mode    = "required"
  auth_token_wo              = ephemeral.aws_secretsmanager_random_password.auth_token.random_password
  auth_token_wo_version      = 1

  snapshot_retention_limit = var.snapshot_retention_limit

  auto_minor_version_upgrade = false
  apply_immediately          = false

  tags = {
    Name = "${var.name}-redis"
  }
}
