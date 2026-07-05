# Deliberate decisions (and why)

Not everything unusual in this lab is an oversight. These are choices
made consciously, with the trade-offs written down so future-me doesn't
"fix" them at 2am — or re-litigate them every audit.

## Security posture (audit 2026-07-04)

- **Only WAN-open port is 51820/udp (WireGuard).** WireGuard doesn't
  respond to unauthenticated probes, so the server is silent to port
  scanners. The old 443 forward was removed as unused. Everything else
  (SSH, RDP, all web UIs) is LAN/VPN only.
- **UFW stays disabled.** With one silent UDP port on WAN and a trusted
  LAN, host firewall adds mystery-breakage risk (Docker publishes ports
  around UFW anyway, which makes the rules misleading). A ready-to-run
  ruleset is staged at `~/security-audit/ufw-enable.sh` if the calculus
  changes. Quick test if it's ever enabled and something breaks:
  `sudo ufw disable`.
- **SSH keeps password auth** until key login is confirmed working from
  every device I actually use. Locking yourself out of a headless box
  to satisfy a checklist is a worse outcome. Zero failed SSH attempts
  in auth.log ever — it has never been internet-exposed.
- **LAN trust model:** devices on my LAN are trusted. SilverBullet,
  Prowlarr, Glances, Prometheus, Homepage, Scrutiny are reachable
  without auth on the LAN, and that's accepted. Remote access is only
  via WireGuard/Tailscale, which inherit the same trust.
- **Samba guest is read-only** (see the samba runbook): guest *read*
  of the media share is the convenience/risk trade I accept; guest
  *write* was a bug and is off.

## Update strategy

- **Watchtower auto-updates most containers** (2h poll, ntfy
  notifications) — for a homelab, stale images are a bigger real risk
  than a bad update.
- **Excluded from auto-update:** Pi-hole, Unbound, WireGuard
  (`com.centurylinklabs.watchtower.enable=false`). These are the
  services whose failure takes down DNS or remote access for the whole
  house — they get updated manually, when I'm home.

## Storage & data protection

- ZFS mirror (2× 16 TB) for `/vault`; SSD landing zone for torrent
  churn so the mirror only sees completed files.
- **Sanoid snapshots** every 15 min on `vault` (24 hourly / 7 daily /
  4 weekly / 3 monthly, autoprune). Recovery is a copy out of
  `/vault/.zfs/snapshot/<name>/`.
- Snapshots protect against deletion/ransomware on the share, **not**
  against pool loss. Offsite backup of irreplaceable data (photos) is
  the known gap on the roadmap.

## Known accepted debt

- Some service passwords are reused and live in plaintext configs.
  Acknowledged; secrets cleanup is planned alongside a Vaultwarden
  deployment (blocked on HTTPS story → Cloudflare Tunnel).
- Router UPnP setting still needs verifying/disabling.
