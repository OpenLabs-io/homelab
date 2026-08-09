#!/bin/bash
# Backs up live configs into ./local/ (gitignored — contains real secrets).
# The committed configs/ dir holds SANITIZED copies only; sanitize by hand
# (or with sanitize-configs.sh) after reviewing diffs.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO/local"
STAMP=$(date +%Y%m%d-%H%M%S)

mkdir -p "$OUT"

# Portainer compose files live in a root-owned volume; use a throwaway
# alpine container to copy them out and chown to the invoking user.
docker run --rm \
  -v portainer_data:/pd:ro \
  -v "$OUT":/out \
  alpine sh -c "rm -rf /out/portainer-compose && cp -r /pd/compose /out/portainer-compose && chown -R $(id -u):$(id -g) /out/portainer-compose"

# User-owned config trees
rsync -a --delete /home/<user>/docker/unbound/          "$OUT/unbound/"
rsync -a --delete /home/<user>/docker/homepage-config/  "$OUT/homepage-config/"
rsync -a --delete /home/<user>/docker/scrutiny-config/  "$OUT/scrutiny-config/"
rsync -a --delete /home/<user>/docker/ntfy-config/      "$OUT/ntfy-config/"
rsync -a --delete /home/<user>/scripts/                 "$OUT/host-scripts/"
[ -d /mnt/tank/apps/monitoring ] && rsync -a --delete /mnt/tank/apps/monitoring/ "$OUT/monitoring/"

# Caddy: ONLY the Caddyfile — data/ and config/ hold private keys and certs
mkdir -p "$OUT/caddy"
cp /home/<user>/docker/caddy/Caddyfile "$OUT/caddy/Caddyfile"

# GPU box power control — the relay half lives here…
rsync -a --delete /home/<user>/docker/mothership-power/ "$OUT/mothership-power/"

# …and the agent half lives on the GPU box. Pulled over ssh; skipped without
# a hard failure when that machine is asleep, which is its normal state.
mkdir -p "$OUT/mothership-agent"
MS_SSH="ssh -o BatchMode=yes -o ConnectTimeout=5 -i $HOME/.ssh/id_ed25519_mothership <user>@<MOTHERSHIP_IP>"
if $MS_SSH true 2>/dev/null; then
  $MS_SSH 'cat /usr/local/bin/mothership-power'        > "$OUT/mothership-agent/mothership-power"
  $MS_SSH 'systemctl cat mothership-power.service'     > "$OUT/mothership-agent/mothership-power.service"
else
  echo "NOTE: GPU box unreachable (probably powered off) — kept last agent copy."
fi

# fail2ban: jail + filter definitions only (data/ also has its ban DB)
mkdir -p "$OUT/fail2ban"
rsync -a --delete /home/<user>/docker/fail2ban/data/jail.d/   "$OUT/fail2ban/jail.d/"
rsync -a --delete /home/<user>/docker/fail2ban/data/filter.d/ "$OUT/fail2ban/filter.d/"

echo "Backup complete: $OUT ($STAMP)"
echo "REMINDER: local/ is gitignored on purpose. Never commit it."
