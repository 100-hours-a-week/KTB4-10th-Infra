#!/bin/bash
set -euo pipefail

# 같은 ECS 클러스터에 등록하고, AI Service만 배치되도록 속성 지정
cat <<EOF >> /etc/ecs/ecs.config
ECS_CLUSTER=${cluster_name}
ECS_INSTANCE_ATTRIBUTES={"workload":"ai"}
ECS_ENABLE_TASK_IAM_ROLE=true
EOF
