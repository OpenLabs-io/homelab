# Deliberate decisions (and why)

Not everything unusual in this lab is an oversight. These are choices
made consciously, with the trade-offs written down so future-me doesn't
"fix" them at 2am — or re-litigate them every audit.

## Security posture (audit 2026-07-04)

- **WAN-open ports: 51820/udp (WireGuard) and, since 2026-07-12,
  443/tcp.** WireGuard doesn't respond to unauthenticated probes, so it
  is silent to scanners. 443 fronts exactly one public service
  (Jellyfin, for a friend without VPN) through Caddy; every other vhost
  on the same port aborts non-private source IPs (see the shared-proxy
  runbook). Everything else (SSH, RDP, all web UIs) is LAN/VPN only,
  verified from an external vantage point — not just from the LAN.
- **Hostname secrecy is not a security boundary.** Internal hostnames
  appear in this repo's Caddyfile; that's deliberate. Access control is
  the source-IP guard + no public DNS records + a wildcard cert keeping
  names out of CT logs. Defense that collapses if someone learns a
  hostname isn't defense.
- **Geo-blocking for the public service: skipped.** Bots rent US
  proxies, and with UFW off there's no clean enforcement point.
  fail2ban (5 fails/10 min → 24 h, in the DOCKER-USER chain) plus
  per-account lockouts do the actual work. If log noise ever gets bad,
  the fallback is Cloudflare proxy + country WAF rules — accepting
  their streaming-throttle caveat.
- **Jellyfin's admin account keeps unlimited login attempts** while all
  other accounts lock after 5 failures. Account lockout on the admin
  hands any attacker a denial-of-service button against the owner;
  fail2ban already rate-limits by IP.
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

## External perimeter verification (2026-07-19)

- **Black-box external scan done and clean.** Checked from a genuine
  off-net vantage (phone on cellular, Wi-Fi off) against the WAN IP,
  because a scan that hairpins back through the router or the local
  resolver proves nothing. Only two ports answer, both intentional:
  - **443/tcp** → Jellyfin via Caddy (public, so friends/family can
    stream without VPN).
  - **51820/udp** → WireGuard (silent to unauthenticated probes).
  No stray forwards, no UPnP surprises — the perimeter matches intent
  exactly.
- **Jellyfin is intentionally public — hardened in place, not moved
  behind the VPN.** It's the one service meant to be shared. Quick
  Connect stays on for TV-app logins. Login brute-force is covered by
  fail2ban, not Caddy rate-limiting: this Caddy build lacks the
  rate_limit module, and adding the directive breaks every site.
- **fail2ban trusts the proxy correctly.** Jellyfin honors Caddy's
  forwarded-for header, so auth-fail logs record the real client IP —
  fail2ban bans the attacker, not the reverse proxy.
- **fail2ban jail-glob staleness fixed durably.** The jail's log-path
  glob wasn't picking up the daily-rotated Jellyfin log, so the jail
  went blind for a few days. A small reload script on a 6-hourly cron
  re-globs it so a fresh day's log is always watched.

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

## Vaultwarden & the domain (2026-07-12)

- **Bought a real domain instead of using Cloudflare Tunnel.** DuckDNS
  couldn't pass any Let's Encrypt challenge, and a tunnel would put the
  password vault behind third-party infrastructure. A ~$10/yr domain at
  Cloudflare Registrar enables DNS-01 certs for everything, split-horizon
  internal HTTPS, and doubles as a future public site.
- **The vault is reachable only from LAN/WireGuard** — no tunnel, no
  public DNS record, and the reverse proxy aborts external IPs even
  though 443 is forwarded. Remote vault access rides the VPN, same as
  everything else.
- Vaultwarden signups closed after the one account; admin panel
  disabled (no ADMIN_TOKEN). Nightly online SQLite backup + restore
  test verified before trusting it with real passwords.

## GPU box: remote power control & telemetry (2026-08-08)

- **Inference runs on a separate workstation, woken on demand.** The
  always-on server has no usable GPU. Rather than leave a workstation
  idling 24/7, it sleeps and is woken by a magic packet from a dashboard
  tile, then powered off the same way.
- **The chat UI lives on the SERVER, not the GPU box.** Only model
  inference is remote. This keeps the web UI and all chat history
  reachable while the GPU machine is asleep — otherwise the dashboard
  would lose a service every time the box powered down.
- **Shutdown is relayed through the server, not linked directly.** A
  dashboard `href` is opened by the client's browser, so a direct link
  would arrive from a phone or VPN address. Relaying means the GPU box
  trusts exactly one host, the tiles work from any client address, and
  its token never reaches a browser.
- **Wake and poweroff use different tokens.** Originally one shared
  token; split because the wake link is the one that ends up bookmarked,
  pasted and in browser history — and it was one click from killing a
  running session. Everything behind that name is guarded by a single
  `import internal_only` line in the reverse proxy, so the token is the
  last line of defence and the poweroff one should not be the casual one.
- **GPU telemetry is read from sysfs and passed through untouched.** The
  relay forwards unknown JSON keys from the agent straight to the
  dashboard, so new metrics need a change on one machine, not two.
- **Accepted:** the GPU box now runs sshd with password auth and has no
  fail2ban. Key-only is the intended end state but was deferred — the
  only key on it is the server's, `from=`-restricted, so going key-only
  remotely would have locked out phone access to a machine with no other
  remote path (no RDP, no Cockpit).

## Known accepted debt

- ~~Some service passwords are reused and live in plaintext configs.~~
  **Resolved 2026-07-12:** every service got a unique generated
  password stored in Vaultwarden; compose-embedded secrets moved to
  Portainer's env store (files reference `${VARS}` only). See the
  password-rotation runbook. Remaining plaintext is the irreducible
  minimum: read-only/least-privilege API keys the dashboard needs,
  accepted under the LAN trust model.
- ~~Router UPnP setting still needs verifying/disabling.~~ Verified
  disabled 2026-07-12.
