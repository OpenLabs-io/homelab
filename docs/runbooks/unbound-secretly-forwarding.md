# Unbound was silently forwarding instead of recursing

**Date solved:** 2026-07-02

## Symptom

DNS worked fine, so nothing *looked* broken. But the whole point of
running Unbound is recursive resolution (no third party sees your full
query history), and the config contained a `forward-zone` sending every
query to 1.1.1.1 and 8.8.8.8. It was a Pi-hole with extra steps.

Check whether you're actually recursing:

```bash
grep -A3 "forward-zone" /home/<user>/docker/unbound/unbound.conf
```

If a `forward-zone: name: "."` block with `forward-addr` lines exists,
you're forwarding, not recursing.

## Root cause

The upstream container image / example config shipped with a
forward-zone block and I never audited it after deploying.

## Fix

Edit `/home/<user>/docker/unbound/unbound.conf`:

1. Delete the entire `forward-zone` block.
2. Ensure recursion + DNSSEC are configured in the `server:` block:

```
root-hints: "/opt/unbound/etc/unbound/root.hints"
auto-trust-anchor-file: "/opt/unbound/etc/unbound/root.key"
qname-minimisation: yes
prefetch: yes
edns-buffer-size: 1232
msg-cache-size: 64m
rrset-cache-size: 128m
```

3. Validate before restarting (bad config = no DNS for the whole LAN):

```bash
docker exec unbound unbound-checkconf /opt/unbound/etc/unbound/unbound.conf
docker restart unbound
```

## Verify

```bash
# Resolution works
dig @127.0.0.1 -p 5335 example.com

# DNSSEC validation works — this domain is deliberately broken and MUST fail
dig @127.0.0.1 -p 5335 dnssec-failed.org   # expect: SERVFAIL

# A signed domain should carry the 'ad' (authenticated data) flag
dig @127.0.0.1 -p 5335 +dnssec cloudflare.com | grep flags
```

## Lesson

"It resolves" is not the same as "it's doing what I deployed it for."
Audit configs you copied from an image or a tutorial.
