variable "name" {
  description = "리소스 식별 이름"
  type        = string
}

# ---------- 서버 ----------

variable "subnet_id" {
  description = "Monitoring 서버를 둘 private-app subnet ID"
  type        = string
}

variable "private_ip" {
  description = "Monitoring 서버 사설 IP (subnet 범위 안, 사용 중이지 않은 값)"
  type        = string
}

variable "security_group_id" {
  description = "Monitoring security group ID"
  type        = string
}

variable "instance_profile_name" {
  description = "Monitoring instance profile 이름"
  type        = string
}

variable "ami_id" {
  description = "Monitoring 서버 AMI ID (Ubuntu, 고정. 바꾸면 서버가 교체됨)"
  type        = string
}

variable "instance_type" {
  description = "Monitoring 서버 인스턴스 타입"
  type        = string
}

variable "root_volume_size" {
  description = "루트 볼륨 크기 (GiB, Prometheus·Grafana 데이터 포함)"
  type        = number
  default     = 20
}

# ---------- 컨테이너 ----------

variable "prometheus_image" {
  description = "Prometheus 이미지"
  type        = string
}

variable "grafana_image" {
  description = "Grafana 이미지"
  type        = string
}

variable "mysqld_exporter_image" {
  description = "mysqld-exporter 이미지"
  type        = string
}

variable "retention_time" {
  description = "Prometheus 보존 기간"
  type        = string
  default     = "90d"
}

# 디스크 20 GiB 기준. WAL은 제한에 포함되지 않아 여유를 둠
variable "retention_size" {
  description = "Prometheus 최대 저장 용량"
  type        = string
  default     = "8GB"
}

# ---------- 수집 대상 ----------

variable "ecs_host_name_tag" {
  description = "ECS Host EC2 Name 태그 (Prometheus EC2 탐색)"
  type        = string
}

variable "ai_name_tag" {
  description = "AI 서버 EC2 Name 태그 (Prometheus EC2 탐색)"
  type        = string
}

variable "ai_private_ip" {
  description = "AI 서버 사설 IP"
  type        = string
}

variable "ai_port" {
  description = "AI 서버 포트 (/metrics)"
  type        = number
}

variable "management_port" {
  description = "Backend 관리 포트 (/actuator/prometheus)"
  type        = number
}

variable "node_exporter_port" {
  description = "node-exporter 포트"
  type        = number
}

variable "cadvisor_port" {
  description = "cAdvisor 호스트 포트"
  type        = number
}

variable "db_address" {
  description = "RDS 엔드포인트 호스트"
  type        = string
}

variable "db_port" {
  description = "RDS 포트"
  type        = number
}

variable "db_username" {
  description = "mysqld-exporter용 RDS 계정 이름 (PROCESS, REPLICATION CLIENT 권한)"
  type        = string
}
