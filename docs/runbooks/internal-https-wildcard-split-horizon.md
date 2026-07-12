# Real HTTPS for every internal service: wildcard cert + split-horizon DNS

**Date solved:** 2026-07-12

## Symptom

Every service lived at an `IP:port` bookmark (`http://<LAN_IP>:3000`,
`https://<LAN_IP>:9443` with a self-signed warning…). Wanted proper
names with valid TLS — `homepage.`, `grafana.`, `immich.`, etc. — that
work identically on LAN and WireGuard, **without** making anything
internet-reachable or even internet-visible.

## Root cause (of why this is normally awkward)

- HTTP-01 cert validation requires the CA to reach your server —
  a non-starter for private services.
- Issuing an individual Let's Encrypt cert per hostname publishes every
  name to Certificate Transparency logs (crt.sh), handing out a map of
  your internal services.
- With 443 already port-forwarded (one public service), every new vhost
  on the shared proxy is one forgotten guard away from being public.

## Fix

**1. One wildcard cert** (`*.<domain>`) via DNS-01: Caddy proves domain
ownership by writing a TXT record through a scoped Cloudflare API token,
so the CA never connects to the server, and CT logs only ever show the
wildcard — individual hostnames stay unlisted.

**2. Split-horizon DNS:** no public records at all. Pi-hole serves the
names locally:

```bash
# NOTE: pass the FULL array every time — this REPLACES the list
docker exec pihole pihole-FTL --config dns.hosts \
  '["<LAN_IP> homepage.<domain>", "<LAN_IP> grafana.<domain>", ...]'
```

WireGuard peers already use Pi-hole as their DNS, so names resolve on
the road too. Deliberately did **not** use a dnsmasq wildcard
(`address=/<domain>/<LAN_IP>`) — it would hijack the apex and any future
*public* record on the same domain for LAN clients.

**3. One wildcard site block in Caddy**, guard first, then a host
matcher per service; unknown subdomains die:

```caddyfile
*.<domain> {
    import dns01
    import internal_only        # external IPs: abort (443 is WAN-open)

    @homepage host homepage.<domain>
    handle @homepage {
        reverse_proxy <LAN_IP>:3000
    }
    # ...one matcher+handle per service...

    handle {
        abort                   # unmatched subdomain → drop
    }
}
```

Adding a service is now: Pi-hole record → matcher+handle → restart.
(Bind-mounted single-file Caddyfile gotcha: `docker restart caddy`, not
reload — reload sees the stale inode and reports "config unchanged".)

**4. Per-app quirks hit along the way:**

| App | Quirk | Fix |
|---|---|---|
| Home Assistant | 400 "request from a reverse proxy" | `http:` block with `use_x_forwarded_for` + `trusted_proxies: <bridge subnet>`; validate via `/api/config/core/check_config` before restarting |
| qBittorrent | rejects unknown Host header | `header_up Host <LAN_IP>:8080` in the proxy block |
| Portainer | speaks HTTPS itself (self-signed) | `reverse_proxy https://…` + `tls_insecure_skip_verify` (traffic never leaves the box) |
| Homepage | validates allowed hosts | `HOMEPAGE_ALLOWED_HOSTS` env (was already `*`) |
| Pi-hole UI | lives under `/admin` | `redir / /admin/ 302` |

## Verify

- All 19 subdomains return 200 or their normal login redirect.
- `openssl s_client -servername homepage.<domain>` → subject
  `CN = *.<domain>`.
- A made-up subdomain → connection dropped with no HTTP response.
- External scan: still only 443 open; internal names get NXDOMAIN from
  public resolvers; crt.sh shows the wildcard only.

## Lesson

DNS-01 decouples "has a valid public cert" from "is publicly reachable"
— private services can have real TLS. And treat Certificate Transparency
as the public bulletin board it is: per-host certs leak your service
inventory; a wildcard doesn't.
