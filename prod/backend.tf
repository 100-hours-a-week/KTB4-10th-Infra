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

    # Tour API (V1과 동시 실행 방지, 전환 시 활성화)
    TOUR_API_SCHEDULER_ENABLED = "false"

    # 웹 푸시
    WEB_PUSH_VAPID_PUBLIC_KEY = "BNZ3naXJsQwUgRjK5S1RMQP00mDtF_SBpTDXya5FdleUIJ2SDU2F32AYvYtcYr-BGKNWbA08MYzB0VGfxw7HXcM"
    WEB_PUSH_VAPID_SUBJECT    = "https://kguidebook.site/"
  }
}
