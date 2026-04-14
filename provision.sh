#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

echo "==> Switching to archive.ubuntu.com mirror (box default is flaky)..."
sed -i 's|mirrors.edge.kernel.org/ubuntu|archive.ubuntu.com/ubuntu|g' /etc/apt/sources.list

echo "==> Installing Docker..."
apt-get update
apt-get install -y docker.io

echo "==> Enabling Docker and adding vagrant to docker group..."
systemctl enable --now docker
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
