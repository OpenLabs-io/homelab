# Portainer stack containers became "orphaned" and unmanageable

**Date solved:** 2026-07-02

## Symptom

The DNS stack (Pi-hole + Unbound) showed in Portainer, but stack
operations (update, redeploy) didn't affect the actual running
containers. Editing the compose file in Portainer and redeploying
changed nothing.

## Root cause

Docker Compose ties containers to a stack via the
`com.docker.compose.project` label. At some point these containers had
been recreated *outside* Portainer (manual `docker run` / a compose
invocation from a temp directory), so:

- `pihole` had **no** project label at all
- `unbound` had `project=tmp`

Portainer's stack 72 therefore owned zero of the containers it
displayed. Check for this:

```bash
docker inspect pihole --format '{{ index .Config.Labels "com.docker.compose.project" }}'
```

## Fix

Remove the orphans and redeploy through Portainer so labels are
correct (≈1 minute of DNS downtime — do it when the house isn't
streaming):

```bash
docker rm -f pihole unbound
# then Portainer → Stacks → dns-core → Update the stack (or via API)
```

Re-inspect: both containers should now carry the stack's project label.

## Lesson

Pick **one** owner for container lifecycle and never go around it. If
Portainer manages a stack, every recreate goes through Portainer —
each manual `docker run` "quick fix" forks reality away from what your
management layer believes, and you find out at the worst time.
