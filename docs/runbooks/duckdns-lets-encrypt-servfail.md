# Let's Encrypt certificates fail on DuckDNS domains

**Date encountered:** 2026-06-28 (attempted Vaultwarden + Caddy, reverted cleanly)

## Symptom

Every Let's Encrypt challenge type failed for `*.duckdns.org`:

- **DNS-01**: LE's validators got SERVFAIL from DuckDNS nameservers
- **HTTP-01 / TLS-ALPN-01**: same story — validation lookups of the
  domain itself SERVFAIL'd intermittently

Caddy retried forever; no cert was ever issued.

## Root cause

DuckDNS's nameservers intermittently return SERVFAIL to Let's
Encrypt's multi-perspective validators (LE validates from several
vantage points; all must succeed). This is a known, long-standing
DuckDNS reliability issue — nothing on my end was misconfigured.

Bonus limitation discovered: DuckDNS doesn't support sub-subdomains
(`vaultwarden.mydomain.duckdns.org` doesn't resolve), so you can't
split services by hostname anyway.

## Resolution

Abandoned certificates on DuckDNS entirely. Options that actually work:

1. **Cloudflare Tunnel** — no open ports, no cert management, free.
   The plan for Vaultwarden.
2. **Real domain (~$10/yr) + Cloudflare DNS** — DNS-01 via Cloudflare
   API is rock solid and gives wildcard certs.

DuckDNS remains fine for what it's good at: a dynamic-DNS target for
the WireGuard endpoint, where no certificate is involved.

## Lesson

When a certificate issuance fails, check *whose* DNS answers the
validator before debugging your own stack. `dig @ns1.duckdns.org
yourdomain.duckdns.org` from an outside box tells you in ten seconds
whether the problem is even yours. Free infrastructure is worth what
you paid for it when a third party's nameserver is in your critical
path.
