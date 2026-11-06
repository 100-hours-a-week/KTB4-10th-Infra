# ---------- Redis (콘솔에서 생성, Valkey 단일 노드, 전송 암호화 + 인증 토큰) ----------
# 인증 토큰 값은 Terraform이 관리하지 않음 (Secrets Manager 값을 콘솔/CLI로 관리)

resource "aws_security_group" "redis" {
  name        = "kgb-prod-redis-sg"
  description = "Security group for KGB ElastiCache Valkey"
  vpc_id      = module.network.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "redis_from_ecs_host" {
  security_group_id = aws_security_group.redis.id
  description       = "ECS Backend Security Group"

  ip_protocol                  = "tcp"
  from_port                    = 6379
  to_port                      = 6379
  referenced_security_group_id = module.security.ecs_host_security_group_id
}

resource "aws_vpc_security_group_egress_rule" "redis_all" {
  security_group_id = aws_security_group.redis.id

  ip_protocol = "-1"
  cidr_ipv4   = "0.0.0.0/0"
}

resource "aws_elasticache_subnet_group" "redis" {
  name        = "kgb-redis-subnet-group"
  description = "Private subnets for KGB ElastiCache"
  subnet_ids  = module.network.private_db_subnet_ids
}

resource "aws_cloudwatch_log_group" "redis_slow_log" {
  name = "/kgb-prod/redis/slow-log"
}

# Backend가 REDIS_PASSWORD로 주입받는 값 (secret만 관리, 값은 관리하지 않음)
resource "aws_secretsmanager_secret" "redis_auth_token" {
  name        = "kgb-prod/redis/auth-token"
  description = "auth token"
}

resource "aws_elasticache_replication_group" "redis" {
  replication_group_id = "kgb-prod-redis"
  description          = "KGB Production Valkey Cache"

  engine               = "valkey"
  engine_version       = "8.2"
  parameter_group_name = "default.valkey8"
  node_type            = "cache.t4g.micro"
  port                 = 6379

  # 단일 노드 (복제본, 자동 장애 조치 없음)
  num_cache_clusters         = 1
  automatic_failover_enabled = false
  multi_az_enabled           = false

  subnet_group_name  = aws_elasticache_subnet_group.redis.name
  security_group_ids = [aws_security_group.redis.id]

  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  transit_encryption_mode    = "required"

  snapshot_retention_limit = 1
  snapshot_window          = "01:30-02:30"
  maintenance_window       = "mon:07:00-mon:08:00"

  auto_minor_version_upgrade = true

  log_delivery_configuration {
    destination      = aws_cloudwatch_log_group.redis_slow_log.name
    destination_type = "cloudwatch-logs"
    log_format       = "json"
    log_type         = "slow-log"
  }
}
