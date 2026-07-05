# Pi-hole v6 env-var and port quirks

**Date solved:** 2026-06-28

## Symptom

After Pi-hole updated to v6, the compose file's settings silently
stopped applying: the web password env did nothing, the upstream DNS
env did nothing, and Pi-hole grabbed port 443 on the host (host-network
container), colliding with anything else that wanted it.

## Root cause

Pi-hole v6 renamed essentially every environment variable, and old v5
names are ignored. It also enables an HTTPS listener on :443 by
default. My compose file still had v5 vars and described a bridge
network the container wasn't even using (it runs host-network).

## Fix

v5 → v6 env var translation (the ones that bit me):

| v5 (dead) | v6 |
|-----------|----|
| `WEBPASSWORD` | `FTLCONF_webserver_api_password` |
| `PIHOLE_DNS_` | `FTLCONF_dns_upstreams` |
| *(web port was lighttpd config)* | `FTLCONF_webserver_port` |
| *(no HTTPS in v5)* | `FTLCONF_webserver_tls_port` |

My working v6 environment (host network):

```yaml
environment:
  FTLCONF_webserver_api_password: "<REDACTED>"
  FTLCONF_dns_upstreams: "127.0.0.1#5335"   # Unbound, also host-network
  FTLCONF_webserver_port: "8090"             # keep :80 free
  FTLCONF_webserver_tls_port: "0"            # 0 = disable the :443 listener
```

## Verify

```bash
# Admin UI on the new port
curl -sI http://<LAN_IP>:8090/admin | head -1

# Nothing on 443 anymore
ss -tlnp | grep :443

# Upstream really is Unbound: blocked domain → 0.0.0.0, normal domain resolves
dig @<LAN_IP> doubleclick.net +short     # expect 0.0.0.0
dig @<LAN_IP> example.com +short         # expect a real IP
```

## Lesson

Major-version container upgrades can invalidate your entire
environment block without a single error message. After any major bump,
diff your compose env against the image's current docs — and check what
ports the container actually binds (`ss -tlnp`) vs what you think it
binds.
