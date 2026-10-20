# Backend 컨테이너 일반 환경 변수 (prod/backend.tf 기준, 주소만 staging)
locals {
  backend_environment = {
    SPRING_PROFILES_ACTIVE = "prod"

    # DB (staging RDS, V1 테스트 Backend와 같은 DB와 계정)
    DB_URL      = "jdbc:mysql://${module.rds.address}:${module.rds.port}/${var.db_name}"
    DB_USERNAME = var.backend_db_username

    # S3
    S3_BUCKET_NAME = var.backend_storage_bucket_name
    AWS_REGION     = "ap-northeast-2"
    # AI ( IP 고정)
    AI_SERVER_BASE_URL        = module.ai.base_url
    AI_SERVER_CONNECT_TIMEOUT = "3s"
    AI_SERVER_READ_TIMEOUT    = "10s"

    # 웹 (staging CloudFront 주소)
    CORS_ALLOWED_ORIGINS  = var.public_base_url
    SESSION_COOKIE_SECURE = "true"

    # 카카오 로그인 (카카오 콘솔에 redirect URI 등록 필요)
    KAKAO_REDIRECT_URI         = "${var.public_base_url}/api/v1/auth/oauth/callback/kakao"
    OAUTH_SUCCESS_REDIRECT_URI = "${var.public_base_url}/auth/complete"
    OAUTH_FAILURE_REDIRECT_URI = "${var.public_base_url}/auth/error"

    # 쿠폰
    COUPON_CREDIT_AMOUNT = "5"

    # Tour API (V1 테스트와 동시 실행 방지, 전환 리허설 때 켜고 끄는 순서 검증)
    TOUR_API_SCHEDULER_ENABLED = "false"

    # 웹 푸시 (공개 키는 prod와 같음. 비공개 키를 넣지 않으면 실제 사용자에게 발송되지 않음)
    WEB_PUSH_VAPID_PUBLIC_KEY = "BNZ3naXJsQwUgRjK5S1RMQP00mDtF_SBpTDXya5FdleUIJ2SDU2F32AYvYtcYr-BGKNWbA08MYzB0VGfxw7HXcM"
    WEB_PUSH_VAPID_SUBJECT    = "${var.public_base_url}/"
  }
}
