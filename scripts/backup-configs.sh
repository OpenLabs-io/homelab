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

# fail2ban: jail + filter definitions only (data/ also has its ban DB)
mkdir -p "$OUT/fail2ban"
rsync -a --delete /home/<user>/docker/fail2ban/data/jail.d/   "$OUT/fail2ban/jail.d/"
rsync -a --delete /home/<user>/docker/fail2ban/data/filter.d/ "$OUT/fail2ban/filter.d/"

echo "Backup complete: $OUT ($STAMP)"
echo "REMINDER: local/ is gitignored on purpose. Never commit it."
