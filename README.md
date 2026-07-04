# Homelab — Self-Hosted Infrastructure

A production-style home server environment I designed, built, and maintain. It runs 24/7 and serves real users (my household), so I treat it like production: uptime matters, changes are versioned, and failures get root-caused.

**Hardware:** Dell Precision tower workstation · Ubuntu Server (headless) · ZFS storage pool
**Orchestration:** Docker + Docker Compose, managed via Portainer

---

## Services

| Service | Role |
|---|---|
| Jellyfin | Media server (streaming to household devices) |
| Immich | Self-hosted photo backup & management |
| Pi-hole v6 | Network-wide DNS filtering / ad & telemetry blocking |
| Unbound | Recursive DNS resolver (upstream for Pi-hole — no third-party DNS) |
| WireGuard | VPN for secure remote access |
| Tailscale | Mesh VPN overlay for device-to-device access |
| Uptime Kuma | Service uptime monitoring & alerting |
| Scrutiny | SMART disk health monitoring |
| Home Assistant | Local-first home automation |

## Network design

- Static LAN IP for the server via NetworkManager, with a matching DHCP reservation at the router
- All client DNS routed through Pi-hole → Unbound (full recursive resolution — queries never touch Google/Cloudflare)
- DNS pushed to LAN clients via DHCP option 6 in dnsmasq
- Containers on isolated Docker bridge networks with fixed addressing for critical services
- Remote access via WireGuard/Tailscale only — nothing exposed to the WAN

## Reliability & automation

- **Versioned config backups:** rsync + Git commit of all Portainer stack configs on a 15-minute systemd timer (see [`backup/`](backup/))
- **Safe shutdown ordering:** docker.service drop-in with hard dependencies on ZFS mount units and an extended stop timeout, so containers always stop before the pool unmounts
- **Database safety:** extended `stop_grace_period` on Postgres (Immich) to guarantee clean flushes on shutdown
- **Self-healing:** `restart: unless-stopped` across all stacks — full recovery from power loss with zero manual intervention

## Problems I've diagnosed and fixed

- **Silent DNS fallback:** Pi-hole queries were being answered by 8.8.8.8 instead of Unbound. Traced via query logs + `dig` timeouts to the Unbound container being unreachable after an IP drift on its bridge network. Fixed with static container addressing and a restart policy to prevent silent recurrence.
- **VPN clobbering local DNS:** Tailscale was overwriting `/etc/resolv.conf` and bypassing Pi-hole. Resolved with `--accept-dns=false`.
- **False disk-failure alerts:** Scrutiny flagged a drive as failed on UDMA CRC errors (attribute 199). Root cause was a faulty SATA cable; after replacing it, the raw counter stays fixed at its historical value, so I retuned Scrutiny's evaluation method to stop alerting on the stale count while still catching new errors.
- **Supply-chain triage:** audited my installed AUR packages against published indicators of compromise during the June 2026 AUR supply-chain attack — reviewing PKGBUILD diffs is now standard practice before any install.

## Windows / Active Directory lab

*(In progress)* — Windows Server evaluation VM with a small AD domain: users, security groups, and Group Policy (password policy, mapped drives, desktop restrictions), plus a domain-joined client VM.

---

## Repo layout

```
compose/     Sanitized Docker Compose files for each stack
backup/      Config backup script + systemd service & timer units
docs/        Network diagram & setup notes
```

> All IPs, hostnames, keys, and secrets in this repo are sanitized placeholders.
