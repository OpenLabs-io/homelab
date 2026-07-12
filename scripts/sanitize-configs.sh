#!/bin/bash
# Rebuilds configs/ (committed, PUBLIC) from local/ (gitignored, raw).
# Copies Portainer compose files under human-readable stack names and
# scrubs every secret. Run backup-configs.sh first.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$REPO/local/portainer-compose"
DST="$REPO/configs/stacks"

[ -f "$REPO/local/identity.map" ] || {
  echo "ERROR: local/identity.map missing — refusing to sanitize without the identity list." >&2
  exit 1
}

declare -A NAMES=(
  [35]=watchtower [37]=uptime-kuma [38]=homepage [44]=speedtest-tracker
  [45]=glances [50]=jellyfin [51]=media-management [56]=duckdns
  [62]=immich [66]=silverbullet [72]=dns-core [73]=wireguard
  [74]=autoheal [75]=scrutiny [76]=ntfy [77]=vaultwarden [78]=fail2ban
)
# NOTE: 77 was the monitoring stack until 2026-07-12; Portainer reused the ID
# for vaultwarden and the monitoring stack entry is gone (its containers still
# run, orphaned). configs/stacks/monitoring/ is kept by hand — see below.

rm -rf "$DST"; mkdir -p "$DST"

# Identity strings (username, home paths, WAN/LAN IPs, ntfy topic, DDNS
# subdomain, personal emails) live in local/identity.map — gitignored, one
# "literal==>placeholder" per line, longest-match first — so this public
# script never contains the values it scrubs.
IDMAP="$REPO/local/identity.map"

scrub_identity() {
  local args=()
  while IFS= read -r line; do
    case "$line" in ''|'#'*) continue ;; esac
    args+=(-e "s|${line%%==>*}|${line#*==>}|Ig")
  done < "$IDMAP"
  sed "${args[@]}"
}

sanitize() {
  # Redact values of secret-bearing keys, but keep ${VAR} placeholders —
  # those are already indirection, and showing them is the point.
  sed -E \
    -e '/\$\{[A-Z_]+\}\s*$/b' \
    -e 's/((PASSWORD|PASSWD|TOKEN|SECRET|API_KEY|APP_KEY|PRIVATE_KEY|api_password)=)[^ "]+/\1<REDACTED>/Ig' \
    -e 's/(password=)[^&"]+/\1<REDACTED>/Ig' \
    -e 's/([A-Za-z0-9_]+:[^@ ]+@)/<REDACTED>@/g' \
    -e 's/(-u +[A-Za-z0-9_]+:)[^ "]+/\1<REDACTED>/g' \
    "$1" | scrub_identity
}

for id in "${!NAMES[@]}"; do
  [ -f "$SRC/$id/docker-compose.yml" ] || continue
  mkdir -p "$DST/${NAMES[$id]}"
  sanitize "$SRC/$id/docker-compose.yml" > "$DST/${NAMES[$id]}/docker-compose.yml"
  if [ -f "$SRC/$id/stack.env" ]; then
    sed -E 's/^([A-Za-z0-9_]+)=.*/\1=<REDACTED>/' "$SRC/$id/stack.env" | scrub_identity > "$DST/${NAMES[$id]}/stack.env"
  fi
done

# Unbound config (no secrets, but sanitize anyway for consistency)
mkdir -p "$REPO/configs/unbound"
sanitize "$REPO/local/unbound/unbound.conf" > "$REPO/configs/unbound/unbound.conf"

# Caddyfile (cert/key material stays in local/ — only the config is public)
mkdir -p "$REPO/configs/caddy"
sanitize "$REPO/local/caddy/Caddyfile" > "$REPO/configs/caddy/Caddyfile"

# fail2ban jail + filter definitions
for sub in jail.d filter.d; do
  mkdir -p "$REPO/configs/fail2ban/$sub"
  for f in "$REPO/local/fail2ban/$sub"/*; do
    [ -f "$f" ] && sanitize "$f" > "$REPO/configs/fail2ban/$sub/$(basename "$f")"
  done
done

# Monitoring stack: orphaned in Portainer (ID reused by vaultwarden) but the
# containers still run from this compose — restore the last committed copy.
git -C "$REPO" restore configs/stacks/monitoring/ 2>/dev/null || true

# Repo-wide identity sweep — covers hand-written docs/runbooks too, not just
# generated configs. Fails loudly so a leak can't slip into a commit.
if hits=$(sed -e '/^#/d' -e '/^$/d' -e 's/==>.*//' "$IDMAP" \
    | grep -rInFi -f - "$REPO" --exclude-dir=.git --exclude-dir=local); then
  echo "LEAK: identity strings found in committed paths — fix before committing:" >&2
  echo "$hits" >&2
  exit 1
fi

echo "Sanitized configs written to configs/. Identity sweep clean. Now AUDIT secrets:"
echo "  grep -rinE 'password|secret|token|key' $REPO/configs | grep -v REDACTED"
