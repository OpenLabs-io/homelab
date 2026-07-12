# Exposing one service to the internet while the rest of the proxy stays private

**Date solved:** 2026-07-12

## Symptom

A friend needed Jellyfin access from an iPhone with no apps and no VPN —
so it had to be plain HTTPS on the open internet. But the reverse proxy
(Caddy) also fronts Vaultwarden and other LAN-only services on the same
port 443. Forwarding 443 for one vhost must not expose the others.

## Root cause (of the design problem)

A router port-forward is all-or-nothing: once 443 → Caddy, *every* site
block Caddy serves is reachable from the WAN unless something inside
Caddy says otherwise. Hostname obscurity doesn't count — public certs
land in Certificate Transparency logs, so attackers can enumerate names.

## Fix

**1. Default-deny snippet in the Caddyfile.** Every site imports it
except the one deliberately public:

```caddyfile
(internal_only) {
    @external not remote_ip private_ranges
    abort @external
}
```

External source IPs get the connection killed before any proxying.
The public Jellyfin block skips the import and adds security headers
(HSTS, nosniff, X-Frame-Options) instead.

**2. DNS:** public A record for the Jellyfin hostname only, DNS-only /
grey-cloud (streaming through Cloudflare's proxy is a ToS problem), kept
current by a `cloudflare-ddns` container. Internal names exist solely in
Pi-hole local records — split horizon.

**3. fail2ban for the exposed app** (`crazymax/fail2ban`, host network,
`NET_ADMIN`), watching Jellyfin's auth failures: 5 fails / 10 min → 24 h
ban. Two gotchas that cost real time:

- **Bans must land in the `DOCKER-USER` chain, not `INPUT`.** Caddy is a
  bridge container with a published port, so its traffic traverses the
  Docker forwarding path — `INPUT` rules never see it and "successful"
  bans block nothing.
- **Jellyfin must be told about the proxy** (`KnownProxies` = the bridge
  subnet in `network.xml`) or every log line shows the proxy's IP as the
  client — which is in `ignoreip`, so fail2ban would never ban anyone.

**4. Account hygiene:** the app's default was *unlimited* login attempts
(`LoginAttemptsBeforeLockout = -1`); set to 5 for every non-admin user.
The admin account deliberately stays unlimited — an attacker who can
trigger admin lockout has a denial-of-service button against the owner,
and fail2ban already rate-limits by IP.

## Verify

From **outside** the LAN. Hairpin NAT didn't work here, so LAN curl
against the WAN IP proves nothing — used check-host.net's API as an
external vantage point:

- 443/tcp: OPEN. 80, 8096 (app direct), 9443 (Portainer): filtered.
- TLS with the wrong/no SNI: handshake refused (no cert to offer).
- The LAN-only vhost from an external address: connection aborted.
- fail2ban end-to-end: deliberate bad logins appear in the jail's
  counters (and LAN IPs are correctly ignored).

## Lesson

Docker-published ports bypass `INPUT` — any firewalling of container
traffic (UFW rules, fail2ban bans) must target `DOCKER-USER` or it's
silently a no-op. And always verify exposure from an external vantage
point; the LAN view lies.
