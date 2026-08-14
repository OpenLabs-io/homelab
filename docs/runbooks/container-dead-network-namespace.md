# Container left in a dead network namespace after its gateway restarts

**Date solved:** 2026-08-04

## Symptom

An application container that routes its traffic through a separate VPN gateway
container showed as `Up` and `healthy` in Docker, but moved no traffic at all.
Its web UI was unreachable and dependent services began reporting it as
unavailable. Nothing had crashed and nothing appeared in the logs, so from the
outside the stack looked completely fine.

## Root cause

The application runs with `network_mode: container:<gateway>`, so it has no
network stack of its own; it borrows the gateway's. When the gateway *restarts*,
that namespace is destroyed and recreated. The application is not restarted with
it, so it keeps a handle on the old, dead namespace: the process is alive and the
container is "Up", but it has no network at all.

Autoheal could not fix this, and in fact caused it. Autoheal has no dependency
ordering. The application's healthcheck reaches the internet *through* the
tunnel, while the gateway deliberately absorbs short VPN blips and retries
internally before reporting unhealthy. So a VPN drop always trips the
application's healthcheck first. Autoheal restarts the application first and the
gateway second, which recreates the exact bug it was supposed to heal.

## Fix

A cron guard running every minute, ordering-safe by construction: it only acts
when the gateway is *already healthy*, so it can never restart the application
into a namespace that is about to be torn down. It also catches namespace
divergence from causes autoheal never sees at all: an automated image update of
the gateway, a stack redeploy, a manual restart.

The test it uses is `gateway -> application web UI on localhost`:

```bash
docker exec "$GATEWAY" wget -q -O /dev/null --timeout=5 \
  http://localhost:"$APP_PORT"/<health-path>
```

That only succeeds if the two containers genuinely share a namespace, so it
detects the split directly rather than inferring it from symptoms.

Guard rails in the script:

- `flock` so overlapping cron runs cannot stack up.
- A 90s minimum gateway age, so its health status is trusted only once settled.
- A 600s restart cooldown, so a genuinely broken application produces one alert
  instead of a restart loop.
- Re-checks after restarting and pushes an alert if recovery failed.

It also re-syncs the gateway's forwarded port. The gateway obtains a new one on
every reconnect, and its own sync hook gives up after roughly 200s, which was
exactly the window the application was missing.

## Verify

```bash
# should exit 0 silently when the namespace is shared
/path/to/netns-guard.sh; echo $?

# both should report the same IP: the VPN exit, not the WAN IP
docker exec "$GATEWAY" wget -qO- https://api.ipify.org; echo
docker exec "$APP"     wget -qO- https://api.ipify.org; echo
```

## Lesson

A container sharing another's network namespace has a dependency that Docker
does not model and healthchecks actively misreport: the dependent container
fails its check *first*, so any naive auto-restarter fixes them in exactly the
wrong order. Health-based automation needs an explicit ordering rule, and the
probe should test the relationship itself rather than a downstream symptom of it.

Note that a *recreate* is different from a *restart*: if the gateway is
recreated, the application must be recreated too (redeploy the stack), because a
container's network mode is fixed at creation time.
