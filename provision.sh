#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

echo "==> Disabling DNSSEC in systemd-resolved (box default breaks DNS)..."
sed -i 's/^DNSSEC=.*/DNSSEC=no/' /etc/systemd/resolved.conf
systemctl restart systemd-resolved

echo "==> Switching to archive.ubuntu.com mirror (box default is flaky)..."
sed -i 's|mirrors.edge.kernel.org/ubuntu|archive.ubuntu.com/ubuntu|g' /etc/apt/sources.list

echo "==> Disabling unattended upgrades (a CI box must not restart Docker mid-build)..."
sed -i 's/^APT::Periodic::Unattended-Upgrade.*/APT::Periodic::Unattended-Upgrade "0";/' /etc/apt/apt.conf.d/20auto-upgrades
systemctl disable --now apt-daily-upgrade.timer unattended-upgrades 2>/dev/null || true

echo "==> Setting timezone..."
timedatectl set-timezone America/Sao_Paulo

echo "==> Growing root filesystem to fill the virtual disk..."
# The box ships a 63 GB LV on a 126 GB partition; the Vagrantfile asks for a
# 150 GB disk. Each step is a no-op when there is nothing left to grow.
ROOT_LV="$(findmnt -no SOURCE /)"
ROOT_PV="$(pvs --noheadings -o pv_name --select "vg_name=$(lvs --noheadings -o vg_name "$ROOT_LV" | tr -d ' ')" | tr -d ' ')"
ROOT_DISK="/dev/$(lsblk -dno PKNAME "$ROOT_PV")"
ROOT_PARTNUM="$(cat "/sys/class/block/$(basename "$ROOT_PV")/partition")"
growpart "$ROOT_DISK" "$ROOT_PARTNUM" || true
pvresize "$ROOT_PV"
lvextend -l +100%FREE "$ROOT_LV" || true
resize2fs "$ROOT_LV"
df -h /

echo "==> Installing Docker (with buildx and compose v2 so host-side builds use BuildKit)..."
apt-get update
apt-get install -y docker.io docker-buildx docker-compose-v2

echo "==> Configuring Docker log rotation and build-cache ceiling..."
# BuildKit's own GC defaults to min(10% of disk, 10 GB) of build cache and
# evicts least-recently-used first, which throws away the cache of rare builds
# (e.g. the Android base image). Raise the ceiling so they survive.
mkdir -p /etc/docker
cat > /etc/docker/daemon.json <<'JSON'
{
  "log-driver": "json-file",
  "log-opts": { "max-size": "50m", "max-file": "3" },
  "builder": {
    "gc": {
      "enabled": true,
      "defaultKeepStorage": "50GB"
    }
  }
}
JSON

echo "==> Enabling Docker and adding vagrant to docker group..."
systemctl enable --now docker
systemctl restart docker
usermod -aG docker vagrant

echo "==> Scheduling weekly Docker cleanup (dangling images + old stopped containers)..."
cat > /etc/cron.weekly/docker-prune <<'CRON'
#!/usr/bin/env bash
# Removes only what no build can reuse: untagged image layers left behind when
# a tag moves to a newer build, and stopped containers older than a week.
# Build cache is governed by the BuildKit GC ceiling in /etc/docker/daemon.json,
# and named volumes (pnpm/gradle caches) are intentionally NOT pruned.
docker image prune -f
docker container prune -f --filter until=168h
CRON
chmod +x /etc/cron.weekly/docker-prune

echo "==> Installing Telegram alerts (disk usage + agent container, every 15 min)..."
install -m 0755 /tmp/agent-alert.sh /usr/local/bin/teamcity-agent-alert
cat > /etc/teamcity-agent-alert.env <<ENV
TELEGRAM_BOT_TOKEN=${TELEGRAM_BOT_TOKEN:-}
TELEGRAM_CHAT_ID=${TELEGRAM_CHAT_ID:-}
DISK_ALERT_PERCENT=${DISK_ALERT_PERCENT:-85}
ENV
chmod 0600 /etc/teamcity-agent-alert.env
cat > /etc/cron.d/teamcity-agent-alert <<'CRON'
*/15 * * * * root /usr/local/bin/teamcity-agent-alert >/dev/null 2>&1
CRON

echo "==> Building TeamCity agent image..."
docker build \
  --build-arg AGENT_NAME="${AGENT_NAME}" \
  --build-arg SERVER_URL="${SERVER_URL}" \
  -t custom-teamcity-agent -f /tmp/Dockerfile.agent /tmp

echo "==> Keeping checkout directories forever (TeamCity default deletes them after 192h)..."
# AGENT_OPTS is appended by the image on the first start, when it generates
# buildAgent.properties. For an agent that already has a config, append here.
AGENT_CONF=/opt/buildagent/conf/buildAgent.properties
EXPIRE_PROP="teamcity.agent.build.checkoutDir.expireHours=never"
mkdir -p /opt/buildagent/conf /opt/buildagent/logs
if [ -f "$AGENT_CONF" ] && ! grep -q "^${EXPIRE_PROP%%=*}=" "$AGENT_CONF"; then
  echo "$EXPIRE_PROP" >> "$AGENT_CONF"
fi

echo "==> Running TeamCity agent container..."
# Recreate so that config/mount changes above take effect on re-provision.
docker rm -f teamcity-agent 2>/dev/null || true
docker run -d --name teamcity-agent \
  --restart unless-stopped \
  -e AGENT_OPTS="$EXPIRE_PROP" \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v /opt/buildagent/conf:/data/teamcity_agent/conf \
  -v /opt/buildagent/logs:/opt/buildagent/logs \
  -v /opt/buildagent/work:/opt/buildagent/work \
  -v /opt/buildagent/temp:/opt/buildagent/temp \
  -v /opt/buildagent/tools:/opt/buildagent/tools \
  -v /opt/buildagent/plugins:/opt/buildagent/plugins \
  -v /opt/buildagent/system:/opt/buildagent/system \
  custom-teamcity-agent

echo "==> Done! TeamCity agent is running."
