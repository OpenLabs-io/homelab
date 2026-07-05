# <ntfy-topic> homelab

Documentation and runbooks for my self-hosted homelab. Every runbook in
`docs/runbooks/` is a real problem I hit and fixed: symptom, root cause,
exact commands.

## Hardware / OS

- Ubuntu Server, 31 GB RAM, server IP `<LAN_IP>`
- WD NVMe 931 GB — OS/root (`/dev/nvme0`)
- Patriot P220 238 GB SSD — download landing zone at `/mnt/landing_zone` (`/dev/sda`)
- 2× Seagate Exos 16 TB — ZFS mirror pool `vault` at `/vault` (`/dev/sdb` + `/dev/sdc`)

## Stack

~24 containers managed as Portainer CE stacks: Jellyfin, Immich, the *arr
media stack behind gluetun (ProtonVPN/WireGuard), Pi-hole + Unbound
(recursive DNS), WireGuard (remote access), Uptime Kuma, Scrutiny, ntfy,
Grafana + Prometheus + cAdvisor, Watchtower, Autoheal, Homepage,
SilverBullet, Home Assistant.

## Repo layout

| Path | What |
|------|------|
| `docs/runbooks/` | One markdown file per solved problem |
| `docs/decisions.md` | Deliberate security/config decisions and why |
| `configs/` | **Sanitized** compose files / configs — secrets replaced with `<REDACTED>` |
| `scripts/backup-configs.sh` | Copies live (unsanitized) configs into `local/` |
| `local/` | **Gitignored** — raw backups with real secrets, never committed |

## Key paths on the server

- Portainer compose files: `/var/lib/docker/volumes/portainer_data/_data/compose/<stack_id>/docker-compose.yml` (root-owned)
- Per-service configs: `/home/<user>/docker/<service>/`
- Unbound config: `/home/<user>/docker/unbound/unbound.conf`
- Monitoring configs: `/mnt/tank/apps/monitoring/` (Prometheus + Grafana provisioning)
- ZFS snapshots (Sanoid, every 15 min): browse at `/vault/.zfs/snapshot/<name>/`
- Host alert scripts: `/home/<user>/scripts/`

## ⚠️ Sanitization policy

Everything committed here must be safe to publish: passwords, API
keys, tokens, and private keys are replaced with `<REDACTED>` or env
placeholders. Raw configs live only in the gitignored `local/` dir.
Before any push, run a secret sweep over tracked files:

```bash
git grep -inE 'password|passwd|secret|token|api.?key|private.?key' | grep -vi 'REDACTED\|example\|placeholder'
```

Remember: git history keeps anything ever committed — if a secret
slips in, rewrite history before pushing, don't just delete the line.
