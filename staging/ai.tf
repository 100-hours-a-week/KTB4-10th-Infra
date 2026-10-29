# AI 컨테이너 환경 변수
locals {
  ai_environment = {
    # LLM_MODE(real/fake)는 Parameter Store /kgb-staging/ai/LLM_MODE에서 주입 (main.tf secret_names)
    # fake 지연 시간 (LLM_MODE=fake일 때만 사용)
    FAKE_LLM_DELAY_SEC = "50"
    SAVE_MODE          = "OFF"

    # 글쓰기 LLM (claude 또는 vllm)
    LLM_WRITE_BACKEND = "vllm"
    VLLM_MODEL        = "kgb-writer"
  }
}
