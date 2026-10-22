# ---------- Redis (콘솔 관리) ----------

# kgb-prod-redis (Valkey, 전송 암호화 + 인증 토큰)
data "aws_elasticache_replication_group" "redis" {
  replication_group_id = "kgb-prod-redis"
}

data "aws_secretsmanager_secret" "redis_auth_token" {
  name = "kgb-prod/redis/auth-token"
}

# Backend 컨테이너 일반 환경 변수
locals {
  backend_environment = {
    SPRING_PROFILES_ACTIVE = "prod"

    # DB (V2 RDS, 전용 계정)
    DB_URL      = "jdbc:mysql://${module.rds.address}:${module.rds.port}/${var.db_name}"
    DB_USERNAME = var.backend_db_username

    # S3
    S3_BUCKET_NAME = var.backend_storage_bucket_name
    AWS_REGION     = "ap-northeast-2"
    # AI ( IP 고정)
    AI_SERVER_BASE_URL        = module.ai.base_url
    AI_SERVER_CONNECT_TIMEOUT = "3s"
    AI_SERVER_READ_TIMEOUT    = "10s"

    # 웹
    CORS_ALLOWED_ORIGINS  = "https://kguidebook.site"
    SESSION_COOKIE_SECURE = "true"

    # 카카오 로그인
    KAKAO_REDIRECT_URI         = "https://kguidebook.site/api/v1/auth/oauth/callback/kakao"
    OAUTH_SUCCESS_REDIRECT_URI = "https://kguidebook.site/auth/complete"
    OAUTH_FAILURE_REDIRECT_URI = "https://kguidebook.site/auth/error"

    # 쿠폰
    COUPON_CREDIT_AMOUNT = "5"

    # Redis (세션, 알림, 쿠폰 시도 횟수). 비밀번호는 Secrets Manager (main.tf)
    REDIS_HOST            = data.aws_elasticache_replication_group.redis.primary_endpoint_address
    REDIS_PORT            = tostring(data.aws_elasticache_replication_group.redis.port)
    REDIS_SSL_ENABLED     = "true"
    REDIS_CONNECT_TIMEOUT = "2s"
    REDIS_COMMAND_TIMEOUT = "2s"

    REDIS_SESSION_NAMESPACE        = "kgb:prod:oauth:session"
    NOTIFICATION_REDIS_ENABLED     = "true"
    NOTIFICATION_REDIS_CHANNEL     = "kgb:prod:notification:sse"
    COUPON_ATTEMPT_REDIS_NAMESPACE = "kgb:prod:coupon:attempt"

    # Tour API (V1과 동시 실행 방지, 전환 시 활성화)
    TOUR_API_SCHEDULER_ENABLED = "true"

    # 웹 푸시
    WEB_PUSH_VAPID_PUBLIC_KEY = "BNZ3naXJsQwUgRjK5S1RMQP00mDtF_SBpTDXya5FdleUIJ2SDU2F32AYvYtcYr-BGKNWbA08MYzB0VGfxw7HXcM"
    WEB_PUSH_VAPID_SUBJECT    = "https://kguidebook.site/"
  }
}
