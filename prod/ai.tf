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
  }
}

# 콘솔에서 먼저 만든 VLLM 비밀 값을 state로 가져옴 (값은 유지)
import {
  to = module.ai.aws_ssm_parameter.secrets["VLLM_BASE_URL"]
  id = "/${var.name}/ai/VLLM_BASE_URL"
}

import {
  to = module.ai.aws_ssm_parameter.secrets["VLLM_API_KEY"]
  id = "/${var.name}/ai/VLLM_API_KEY"
}
