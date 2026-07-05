# Repo maintenance & sanitization policy

How this repo stays in sync with the live server without ever leaking
a secret.

## Workflow

1. `scripts/backup-configs.sh` — copies live configs (Portainer compose
   files, Unbound, Homepage, Scrutiny, ntfy, monitoring, host scripts)
   into `local/`. That directory is **gitignored** and never committed:
   it contains real passwords, API keys, and tokens.
2. `scripts/sanitize-configs.sh` — rebuilds `configs/` from `local/`,
   mapping Portainer stack IDs to readable names and redacting every
   secret-bearing value to `<REDACTED>`. `${VAR}` env indirections are
   kept as-is — they're already placeholders.
3. Audit before committing. Sanitizers have blind spots; grep for the
   patterns *and* for known real values:

```bash
git grep -inE 'password|passwd|secret|token|api.?key|private.?key' \
  | grep -viE 'REDACTED|\$\{[A-Z_]+\}|placeholder'
```

4. Commit and push only after the sweep comes back empty.

## Rules

- `local/` never gets committed. If a secret ever lands in a commit,
  rewrite history before pushing — deleting the line in a later commit
  leaves it in the history forever.
- Commits use the GitHub noreply address; no personal email in
  metadata.
- New secret formats (a new service's token style) get added to both
  the sanitizer and the audit grep.

## Key paths on the live server

- Portainer compose files: `/var/lib/docker/volumes/portainer_data/_data/compose/<stack_id>/docker-compose.yml` (root-owned; the backup script reads them via a throwaway container)
- Per-service configs: `~/docker/<service>/`
- Monitoring configs: `/mnt/tank/apps/monitoring/`
- ZFS snapshots (Sanoid, every 15 min): `/vault/.zfs/snapshot/<name>/`
