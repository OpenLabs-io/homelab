# Immich machine-learning container silently deadlocked

**Date solved:** 2026-06-27

## Symptom

Immich itself worked (uploads, browsing), but smart search and face
recognition had quietly stopped processing new photos. No crash, no
restart, no error in the UI — the ML container had been wedged for
about 7 days before anyone noticed.

## Root cause

The `immich_machine_learning` container runs a single gunicorn worker.
That worker deadlocked; since the *process* was still alive, Docker
considered the container healthy and nothing restarted it.

## Fix

Immediate:

```bash
docker restart immich_machine_learning
```

Structural — make this class of failure self-healing:

1. **Autoheal** container watches Docker healthchecks and restarts any
   container that reports unhealthy.
2. A **health-notifier** sidecar pushes an ntfy notification whenever
   any container flips to unhealthy, so a restart loop doesn't hide a
   real problem.

```yaml
services:
  autoheal:
    image: willfarrell/autoheal
    restart: unless-stopped
    environment:
      AUTOHEAL_CONTAINER_LABEL: all
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
```

## Verify

```bash
docker ps --format '{{.Names}}\t{{.Status}}' | grep immich
# then in the Immich UI: upload a photo, confirm faces/objects get indexed
```

## Lesson

"Container is running" and "service is working" are different claims.
A process can be alive and useless. Healthchecks should test the actual
function (an HTTP endpoint, a real query), and something must *act* on
a failing healthcheck — a red status nobody watches is decoration.
