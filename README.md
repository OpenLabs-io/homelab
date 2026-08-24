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
| Uptime Kuma | Service uptime monitoring & alerting |
| Scrutiny | SMART disk health monitoring |
| Home Assistant | Local-first home automation |
| Open WebUI + Ollama | Local LLM inference — UI on the server, models on a wake-on-demand GPU box |

## Network design

- Static LAN IP for the server via NetworkManager, with a matching DHCP reservation at the router
- All client DNS routed through Pi-hole → Unbound (full recursive resolution — queries never touch Google/Cloudflare)
- DNS pushed to LAN clients via DHCP option 6 in dnsmasq
- Containers on isolated Docker bridge networks with fixed addressing for critical services
- Remote admin via WireGuard; one deliberately public service (Jellyfin) behind a hardened reverse proxy — TLS, fail2ban, account lockouts, externally verified. Everything else LAN/VPN-only with valid HTTPS via a wildcard cert and split-horizon DNS

## Reliability & automation

- **Versioned config backups:** all Portainer stack configs are backed up, sanitized, and versioned in Git (see [`scripts/`](scripts/) and [`docs/maintenance.md`](docs/maintenance.md))
- **Safe shutdown ordering:** docker.service drop-in with hard dependencies on ZFS mount units and an extended stop timeout, so containers always stop before the pool unmounts
- **Database safety:** extended `stop_grace_period` on Postgres (Immich) to guarantee clean flushes on shutdown
- **Self-healing:** `restart: unless-stopped` across all stacks — full recovery from power loss with zero manual intervention
- **On-demand GPU power control:** a second workstation hosts LLM inference and sleeps when idle. Dashboard tiles wake it (Wake-on-LAN magic packet from an always-on relay) and power it off (token-authed shutdown relayed server-side), with live GPU load/watts/temp read from sysfs. See the [runbook](docs/runbooks/wake-on-lan-remote-power-gpu-box.md)

## Problems I've diagnosed and fixed

- **Silent DNS fallback:** Pi-hole queries were being answered by 8.8.8.8 instead of Unbound. Traced via query logs + `dig` timeouts to the Unbound container being unreachable after an IP drift on its bridge network. Fixed with static container addressing and a restart policy to prevent silent recurrence.
- **VPN clobbering local DNS:** while trialing Tailscale, it overwrote `/etc/resolv.conf` and bypassed Pi-hole. Resolved with `--accept-dns=false`; I've since consolidated remote access on WireGuard alone.
- **False disk-failure alerts:** Scrutiny flagged a drive as failed on UDMA CRC errors (attribute 199). Root cause was a faulty SATA cable; after replacing it, the raw counter stays fixed at its historical value, so I retuned Scrutiny's evaluation method to stop alerting on the stale count while still catching new errors.
- **A status page that lied:** the "waking up…" page reported *"no response after 5 minutes"* for a machine that booted in 30 seconds — every time. The page is served over HTTPS and polled a plain-HTTP endpoint, so the browser blocked it as mixed active content and an empty `catch` swallowed the error. Moved the cross-origin hop server-side and gave the page a same-origin path. [Write-up](docs/runbooks/https-page-polling-http-endpoint-mixed-content.md)
- **Supply-chain triage:** audited my installed AUR packages against published indicators of compromise during the June 2026 AUR supply-chain attack — reviewing PKGBUILD diffs is now standard practice before any install.
- **A bypass in my own LLM command gate:** the classifier that lets the local model use `curl` compared whole tokens, but curl accepts short options clustered and with the value attached — so `curl -T file` was refused while `curl -sTfile` uploaded the service's own credentials to an arbitrary host. Caught on an adversarial review pass before it reached the second machine; fixed by expanding option clusters the way curl's own parser does, and covered by a 134-case regression suite. [Write-up](docs/runbooks/llm-command-gate-curl-flag-bypass.md)

Full write-ups — symptom, root cause, exact commands, and the lesson — live in [`docs/runbooks/`](docs/runbooks/).

## Local AI — a private LLM with gated shell access

A local model runs on a wake-on-demand GPU workstation, with the chat front end
and search backend on the always-on server. No prompt, file, or command in this
stack reaches a third-party API.

The model can **run commands on both machines**, which is the part that needed
real design work:

- **One executor service per host, no cross-machine SSH** — the model reaches
  both machines, but neither machine can reach the other. No new keys, no
  lateral path if one host is compromised.
- **Reads run immediately from an allowlist; anything mutating waits for a
  human** — approvals arrive as a phone push with one-tap Approve/Deny, plus an
  expiring session-unlock window for hands-on work.
- **Read commands execute with no shell at all**, so shell injection on that
  path is structurally impossible rather than filtered.
- **Control-plane routes are kept out of the OpenAPI schema.** Open WebUI turns
  every operation in a spec into a model-callable tool — before that was fixed,
  the model could approve its own proposals and unlock its own session.

Full write-up, including the observability design and the tradeoffs that are
accepted rather than solved: [`docs/local-ai.md`](docs/local-ai.md).

## Windows / Active Directory lab

*(In progress)* — Windows Server evaluation VM with a small AD domain: users, security groups, and Group Policy (password policy, mapped drives, desktop restrictions), plus a domain-joined client VM.

---

## Repo layout

```
configs/     Sanitized Docker Compose files for each stack + Unbound config
docs/        Runbooks (root-caused fixes), architecture decisions, maintenance notes,
             and the local-AI design write-up
scripts/     Config backup + sanitization tooling
```

> All IPs, hostnames, keys, and secrets in this repo are sanitized placeholders.

> This lab is built and documented with heavy AI assistance throughout. The goals,
> the architecture decisions, the testing, and the running of these machines are mine.
