# GHCR 비공개 이미지 인증 (Backend, AI 등 같은 조직 이미지에서 공통 사용)
# ECS repositoryCredentials는 Secrets Manager만 지원
# 값은 콘솔/CLI로 직접 입력: {"username":"<GitHub 계정>","password":"<read:packages PAT>"}
resource "aws_secretsmanager_secret" "ghcr" {
  name        = "${var.name}/ghcr"
  description = "GHCR credentials for pulling private container images"

  tags = {
    Name = "${var.name}/ghcr"
  }
}
