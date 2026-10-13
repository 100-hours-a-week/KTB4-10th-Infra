# DB Subnet Group (AZ별 private-db subnet)
resource "aws_db_subnet_group" "main" {
  name        = "${var.name}-db-subnet-group"
  description = "Private DB subnets for RDS"
  subnet_ids  = var.subnet_ids

  tags = {
    Name = "${var.name}-db-subnet-group"
  }
}

# 파라미터 그룹
resource "aws_db_parameter_group" "main" {
  name        = "${var.name}-mysql-params"
  family      = var.parameter_group_family
  description = "MySQL parameters for ${var.name}"

  # V1과 동일한 값
  parameter {
    name  = "sql_mode"
    value = "ONLY_FULL_GROUP_BY,STRICT_TRANS_TABLES,NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION"
  }

  tags = {
    Name = "${var.name}-mysql-params"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# RDS MySQL (Multi-AZ)
resource "aws_db_instance" "main" {
  identifier = "${var.name}-db"

  engine         = "mysql"
  engine_version = var.engine_version
  instance_class = var.instance_class

  # 스토리지 (암호화는 생성 후 변경 불가)
  storage_type          = "gp3"
  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_encrypted     = true

  # 네트워크
  multi_az               = true
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [var.security_group_id]
  publicly_accessible    = false
  port                   = 3306

  # 마스터 계정 (변경 시, version 숫자 올림)
  username            = var.master_username
  password_wo         = var.master_password
  password_wo_version = 1

  db_name              = var.db_name
  parameter_group_name = aws_db_parameter_group.main.name

  # 백업 (시간은 UTC)
  backup_retention_period = var.backup_retention_period
  backup_window           = var.backup_window
  copy_tags_to_snapshot   = true

  # 유지보수 (시간은 UTC, 버전은 직접 올림)
  maintenance_window         = var.maintenance_window
  auto_minor_version_upgrade = false
  apply_immediately          = false

  # 로그
  enabled_cloudwatch_logs_exports = ["error"]

  # 삭제 보호
  deletion_protection       = true
  skip_final_snapshot       = false
  final_snapshot_identifier = "${var.name}-mysql-final"

  tags = {
    Name = "${var.name}-mysql"
  }
}
