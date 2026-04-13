#!/usr/bin/env bash
set -euo pipefail

echo "==> Installing Docker and dependencies..."
pacman -S --noconfirm docker iptables

echo "==> Loading kernel modules..."
modprobe br_netfilter
modprobe overlay

echo "==> Enabling and starting Docker..."
systemctl enable docker
systemctl start docker
systemctl status docker --no-pager

echo "==> Adding vagrant user to docker group..."
usermod -aG docker vagrant

echo "==> Building TeamCity agent image..."
docker build \
  --build-arg AGENT_NAME="${AGENT_NAME}" \
  --build-arg SERVER_URL="${SERVER_URL}" \
  -t custom-teamcity-agent -f /tmp/Dockerfile.agent /tmp

echo "==> Running TeamCity agent container..."
docker run -d --name teamcity-agent \
  --restart unless-stopped \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v /opt/buildagent/work:/opt/buildagent/work \
  -v /opt/buildagent/temp:/opt/buildagent/temp \
  -v /opt/buildagent/tools:/opt/buildagent/tools \
  -v /opt/buildagent/plugins:/opt/buildagent/plugins \
  -v /opt/buildagent/system:/opt/buildagent/system \
  custom-teamcity-agent

echo "==> Done! TeamCity agent is running."
