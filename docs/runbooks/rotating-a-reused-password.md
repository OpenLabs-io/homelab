# Rotating one reused password out of six services (and every consumer)

**Date solved:** 2026-07-12

## Symptom

One password unlocked Grafana, Pi-hole, ntfy, qBittorrent, Uptime Kuma,
and doubled as Watchtower's API token. Worse, copies of it were embedded
in over a dozen consumers: notification URLs in two compose files, a
Scrutiny config, four cron scripts, four dashboard widgets, a
notification row inside Uptime Kuma's SQLite DB, and three *arr
download-client configs. One breach anywhere = everything.

## Root cause

Convenience debt: every new service got "the password" because there
was nowhere trustworthy to keep unique ones. Deploying Vaultwarden
removed that excuse.

## Fix

**Inventory before touching anything.** `grep -rl '<the-password>'`
across every config tree, the Portainer compose volume, and application
databases (Kuma stores notification credentials as JSON inside
`kuma.db`). The rotation itself is trivial — the outage comes from the
consumer you forgot.

**Then rotate service-by-service, most consumers first**, verifying
each before the next: change the service's password, update every
consumer, prove it (test publish for ntfy, API auth checks for
Grafana/Pi-hole, health endpoints for the *arrs). Compose-embedded
copies moved to Portainer's env store — files now say
`${NTFY_PASSWORD}`, the value lives only in Portainer.

**Gotchas that actually bit:**

- **Updating a poller's config before the service = self-inflicted
  brute-force.** The dashboard widget got the new qBittorrent password
  while qBittorrent still had the old one; its retry loop tripped
  qBittorrent's failed-auth IP ban within minutes and locked *me* out.
  Pause pollers (dashboard, *arrs) across the swap window.
- **The qBittorrent env password had NEVER been correct.** The VPN
  container's port-forward hook "worked" for months only because
  `LocalHostAuth=false` bypasses auth from localhost — the credential
  it passed was wrong and nothing ever validated it. Reset by stopping
  the container and writing a fresh hash directly:
  PBKDF2-HMAC-SHA512, 100 000 iterations, 16-byte salt, as
  `WebUI\Password_PBKDF2="@ByteArray(b64salt:b64hash)"`.
  (qBittorrent 5.x returns HTTP 204 with an empty body on successful
  API login — looks like a failure if you expect `Ok.`.)
- ***arr download-client updates 400 on save** if any validation
  warning exists (here: a pre-existing share-ratio complaint).
  `PUT ...?forceSave=true` — the failed validation had already proven
  the new credential worked.
- **Editing the DB-resident copy:** SQL `replace()` on the Kuma
  notification row, then restart Kuma — it caches notification config
  in memory, so a DB edit alone silently does nothing.
- **Stale backup files count.** A forgotten `services.yaml.save` and a
  leftover local compose copy still held the old password after
  everything "live" was clean. The final sweep greps *everything*,
  including app databases, not just the files you remember editing.

## Verify

- Old password rejected / new accepted on every rotated service
  (including a negative test — wrong password → 401).
- Test notification pushed end-to-end through the new ntfy credential.
- *arr health endpoints show no download-client connection errors.
- Final `grep -rl` across home dirs, the Portainer volume, and Kuma's
  DB: zero hits on the old password.

## Lesson

Credentials that are never validated rot silently — the qBittorrent
env var was wrong for months and nothing noticed. Inventory consumers
before rotating, pause anything that polls with stored credentials,
and sweep databases and stale backups, not just config files.
