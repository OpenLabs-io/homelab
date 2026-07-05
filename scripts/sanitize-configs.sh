#!/bin/bash
# Rebuilds configs/ (committed, PUBLIC) from local/ (gitignored, raw).
# Copies Portainer compose files under human-readable stack names and
# scrubs every secret. Run backup-configs.sh first.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$REPO/local/portainer-compose"
DST="$REPO/configs/stacks"

declare -A NAMES=(
  [35]=watchtower [37]=uptime-kuma [38]=homepage [44]=speedtest-tracker
  [45]=glances [50]=jellyfin [51]=media-management [56]=duckdns
  [62]=immich [66]=silverbullet [72]=dns-core [73]=wireguard
  [74]=autoheal [75]=scrutiny [76]=ntfy [77]=monitoring
)

rm -rf "$DST"; mkdir -p "$DST"

sanitize() {
  # Redact values of secret-bearing keys, but keep ${VAR} placeholders —
  # those are already indirection, and showing them is the point.
  sed -E \
    -e '/\$\{[A-Z_]+\}\s*$/b' \
    -e 's/((PASSWORD|PASSWD|TOKEN|SECRET|API_KEY|APP_KEY|PRIVATE_KEY|api_password)=)[^ "]+/\1<REDACTED>/Ig' \
    -e 's/(password=)[^&"]+/\1<REDACTED>/Ig' \
    -e 's/([A-Za-z0-9_]+:[^@ ]+@)/<REDACTED>@/g' \
    -e 's/(-u +[A-Za-z0-9_]+:)[^ "]+/\1<REDACTED>/g' \
    "$1"
}

for id in "${!NAMES[@]}"; do
  [ -f "$SRC/$id/docker-compose.yml" ] || continue
  mkdir -p "$DST/${NAMES[$id]}"
  sanitize "$SRC/$id/docker-compose.yml" > "$DST/${NAMES[$id]}/docker-compose.yml"
  if [ -f "$SRC/$id/stack.env" ]; then
    sed -E 's/^([A-Za-z0-9_]+)=.*/\1=<REDACTED>/' "$SRC/$id/stack.env" > "$DST/${NAMES[$id]}/stack.env"
  fi
done

# Unbound config (no secrets, but sanitize anyway for consistency)
mkdir -p "$REPO/configs/unbound"
sanitize "$REPO/local/unbound/unbound.conf" > "$REPO/configs/unbound/unbound.conf"

echo "Sanitized configs written to configs/. Now AUDIT before committing:"
echo "  grep -rinE 'password|secret|token|key' $REPO/configs | grep -v REDACTED"
