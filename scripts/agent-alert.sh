#!/usr/bin/env bash
# Telegram alerts for the TeamCity agent VM. Runs from cron every 15 minutes.
# Only sends a message when a condition changes (ok -> alert, alert -> ok),
# so a full disk produces one message, not one every 15 minutes.
#
# Config: /etc/teamcity-agent-alert.env (written by provision.sh from .env)
#   TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID, DISK_ALERT_PERCENT (default 85)
#
# Usage: teamcity-agent-alert          # run the checks
#        teamcity-agent-alert --test   # send a test message
set -uo pipefail

CONF=/etc/teamcity-agent-alert.env
[ -f "$CONF" ] && . "$CONF"
THRESHOLD="${DISK_ALERT_PERCENT:-85}"
STATE_DIR=/var/lib/teamcity-agent-alert
HOST="$(hostname)"
mkdir -p "$STATE_DIR"

send() {
  if [ -z "${TELEGRAM_BOT_TOKEN:-}" ] || [ -z "${TELEGRAM_CHAT_ID:-}" ]; then
    echo "telegram not configured; would send: $1"
    return 0
  fi
  curl -fsS -m 15 -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    -d chat_id="${TELEGRAM_CHAT_ID}" --data-urlencode text="$1" >/dev/null
}

# notify <key> <is_bad 0|1> <alert message> <recovery message>
notify() {
  local key=$1 bad=$2 file="$STATE_DIR/$1" prev
  prev="$(cat "$file" 2>/dev/null || echo 0)"
  [ "$bad" = "$prev" ] && return 0
  if [ "$bad" = 1 ]; then send "$3"; else send "$4"; fi
  echo "$bad" > "$file"
}

if [ "${1:-}" = "--test" ]; then
  send "✅ Teste de alerta do agente TeamCity ($HOST)"
  exit $?
fi

USE="$(df --output=pcent / | tail -1 | tr -dc 0-9)"
AVAIL="$(df -h --output=avail / | tail -1 | tr -d ' ')"
notify disk "$([ "$USE" -ge "$THRESHOLD" ] && echo 1 || echo 0)" \
  "🚨 Disco do agente TeamCity ($HOST) em ${USE}% (${AVAIL} livres). Limite: ${THRESHOLD}%." \
  "✅ Disco do agente TeamCity ($HOST) voltou a ${USE}% (${AVAIL} livres)."

RUNNING="$(docker inspect -f '{{.State.Running}}' teamcity-agent 2>/dev/null || echo false)"
notify agent "$([ "$RUNNING" = true ] && echo 0 || echo 1)" \
  "🚨 Container teamcity-agent parado em $HOST." \
  "✅ Container teamcity-agent de volta em $HOST."
