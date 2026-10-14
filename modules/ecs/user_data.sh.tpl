#!/bin/bash
set -euo pipefail

cat <<EOF >> /etc/ecs/ecs.config
ECS_CLUSTER=${cluster_name}
ECS_ENABLE_TASK_IAM_ROLE=true
EOF
