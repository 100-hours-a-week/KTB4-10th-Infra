#!/bin/bash
set -euxo pipefail

# IP 포워딩 (재부팅 후에도 유지)
echo "net.ipv4.ip_forward = 1" > /etc/sysctl.d/90-nat.conf
sysctl -p /etc/sysctl.d/90-nat.conf

# apt 저장소를 HTTPS로 변경 (SG가 아웃바운드 443만 허용)
for f in /etc/apt/sources.list /etc/apt/sources.list.d/ubuntu.sources; do
  [ -f "$f" ] && sed -i 's|http://|https://|g' "$f"
done

# EIP가 붙어 인터넷이 될 때까지 재시도
export DEBIAN_FRONTEND=noninteractive
until apt-get update && apt-get install -y iptables-persistent; do
  sleep 5
done

# 외부로 나가는 패킷의 출발지를 NAT 인스턴스 IP로 변환
IFACE=$(ip -o -4 route show to default | awk '{print $5; exit}')
iptables -t nat -A POSTROUTING -o "$IFACE" -j MASQUERADE

# 재부팅 후에도 규칙 유지
netfilter-persistent save

# Session Manager 접속용 SSM Agent (Ubuntu AMI에 없으면 설치)
snap list amazon-ssm-agent || snap install amazon-ssm-agent --classic
snap start --enable amazon-ssm-agent
