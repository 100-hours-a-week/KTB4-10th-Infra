#!/bin/bash
set -euxo pipefail

# 처음 설치용. 이후 설정 변경은 /opt/monitoring 에서 직접 하고 레포에도 반영

# apt 저장소를 HTTPS로 변경 (SG가 아웃바운드 443만 허용)
for f in /etc/apt/sources.list /etc/apt/sources.list.d/ubuntu.sources; do
  [ -f "$f" ] && sed -i 's|http://|https://|g' "$f"
done

# NAT를 통해 인터넷이 될 때까지 재시도
export DEBIAN_FRONTEND=noninteractive
until apt-get update && apt-get install -y docker.io docker-compose-v2; do
  sleep 10
done

# 컨테이너 로그가 디스크(20 GiB)를 채우지 않도록 크기 제한
cat > /etc/docker/daemon.json <<'KGB_EOF'
{
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" }
}
KGB_EOF
systemctl enable docker
systemctl restart docker

# Session Manager 접속용 SSM Agent, 비밀 값 조회용 AWS CLI
snap list amazon-ssm-agent || snap install amazon-ssm-agent --classic
snap start --enable amazon-ssm-agent
until snap list aws-cli || snap install aws-cli --classic; do
  sleep 10
done

D=/opt/monitoring
mkdir -p $D/prometheus $D/grafana/provisioning/datasources $D/grafana/provisioning/dashboards $D/grafana/dashboards

cat > $D/docker-compose.yml <<'KGB_EOF'
${compose}
KGB_EOF

cat > $D/prometheus/prometheus.yml <<'KGB_EOF'
${prometheus}
KGB_EOF

cat > $D/grafana/provisioning/datasources/prometheus.yml <<'KGB_EOF'
${grafana_datasources}
KGB_EOF

cat > $D/grafana/provisioning/dashboards/default.yml <<'KGB_EOF'
${grafana_dashboards}
KGB_EOF

%{ for name, content in dashboards ~}
cat > $D/grafana/dashboards/${name} <<'KGB_EOF'
${content}
KGB_EOF
%{ endfor ~}

# 비밀 값 (로그에 남지 않도록 출력 끔)
set +x
get() {
  /snap/bin/aws ssm get-parameter --region ${region} --with-decryption \
    --name "$1" --query Parameter.Value --output text
}

# Parameter Store에 실제 값을 넣을 때까지 대기
until G=$(get ${grafana_param}) && [ "$G" != "CHANGE_ME" ] \
  && M=$(get ${exporter_param}) && [ "$M" != "CHANGE_ME" ]; do
  echo "waiting for monitoring secrets in Parameter Store"
  sleep 30
done

# 작은따옴표: Compose가 값 안의 $를 변수로 해석하지 않게
umask 077
printf "GRAFANA_ADMIN_PASSWORD='%s'\nMYSQL_EXPORTER_PASSWORD='%s'\n" "$G" "$M" > $D/.env
unset G M
set -x

cd $D
docker compose up -d
