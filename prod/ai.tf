# AI 컨테이너 환경 변수
locals {
  ai_environment = {
    # 실제 LLM 대신 가짜 응답 (RunPod 연동 전)
    LLM_MODE           = "real"
    FAKE_LLM_DELAY_SEC = "50"
    SAVE_MODE          = "OFF"

    # 글쓰기 LLM (claude 또는 vllm)
    LLM_WRITE_BACKEND = "vllm"
    VLLM_MODEL        = "kgb-writer"

    # 작업 큐 워커 수 (동시 생성 수, 기본 3)
    JOB_WORKERS = "3"

    # Langfuse (키는 Parameter Store)
    LANGFUSE_BASE_URL            = "https://jp.cloud.langfuse.com"
    LANGFUSE_TRACING_ENVIRONMENT = "production"
  }
}
