# AI 컨테이너 환경 변수
locals {
  ai_environment = {
    # 가짜 응답 (부하 테스트 중 API 요금 없음). 실제 생성 확인 시 real + ANTHROPIC_API_KEY 입력
    LLM_MODE           = "real"
    FAKE_LLM_DELAY_SEC = "50"
    SAVE_MODE          = "OFF"

    # 글쓰기 LLM (claude 또는 vllm)
    LLM_WRITE_BACKEND = "vllm"
    VLLM_MODEL        = "kgb-writer"
  }
}
