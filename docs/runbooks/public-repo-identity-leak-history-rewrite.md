# Identity strings leaked into this public repo's git history

**Date solved:** 2026-07-07

## Symptom

Two days after publishing this repo, I noticed the "sanitized" configs
weren't as sanitized as I thought. The sanitize script redacted every
*secret* (passwords, tokens, keys — those were fine, verified across all
history), but identity strings sailed right through: my Linux username
in ~30 places (volume paths, `curl -u`, service logins), my real **WAN
IP** in the WireGuard `SERVERURL`, my LAN IP, an ntfy topic and DDNS
subdomain derived from my username, and one commit authored with a
personal email instead of the GitHub noreply address.

Fixing the files wasn't enough — all of it was still visible in every
prior commit.

## Root cause

The sanitize pass was scoped to *secrets by key name* (`PASSWORD=`,
`TOKEN=`, etc.). Nobody told it a username or an IP was sensitive, and
several leaks were in hand-written runbooks it never scanned at all.
Also: git history is append-only by default, so "fix it in a new
commit" hides nothing.

## Fix

1. Inventory the damage across **all** history, not just the working tree:

```bash
git rev-list --all | while read c; do
  git grep -InE 'yourname|your\.wan\.ip|password=|TOKEN' $c -- 2>/dev/null
done | grep -v REDACTED | sort -u
```

2. Rewrite history with `git-filter-repo` — a replacements file of
`literal==>placeholder` lines (longest match first), plus a mailmap to
normalize commit authorship to the noreply identity:

```bash
pip3 install --user --break-system-packages git-filter-repo
git filter-repo --replace-text replacements.txt --mailmap mailmap.txt --force
git remote add origin <url>   # filter-repo removes the remote on purpose
git push --force origin main
```

3. **Force-push is not enough on GitHub.** The old orphaned commits stay
fetchable by SHA until GitHub garbage-collects them. The guaranteed fix
is deleting and recreating the repo (I had 0 forks/0 stars, so this cost
nothing but the creation date) or a GitHub Support purge ticket.

4. Prevent recurrence: `scripts/sanitize-configs.sh` now applies an
identity-string map from a **gitignored** file (`local/identity.map`) —
so the public script never contains the values it scrubs — and does a
repo-wide sweep of those literals (docs and runbooks included) that
exits non-zero on any hit.

## Verify

```bash
# Zero hits for any leaked string in any commit
git rev-list --all | while read c; do
  git grep -Iine 'yourname|your\.wan\.ip' $c -- 2>/dev/null
done

# Old commit SHA is gone from GitHub (expect "No commit found")
curl -s https://api.github.com/repos/<owner>/<repo>/commits/<old-sha>

# The sweep actually trips: plant a leak, expect exit 1
echo "ssh yourname@your.lan.ip" > docs/leak-test.md
bash scripts/sanitize-configs.sh; echo "exit=$?"   # expect exit=1
rm docs/leak-test.md
```

## Lesson

"Sanitized" means secrets AND identity: usernames, home paths, WAN/LAN
IPs, hostnames, topics/subdomains derived from your name, and commit
author emails. Sweep the whole repo (docs too), sweep all of history,
and make the check fail loudly instead of relying on eyeballs — mine
missed thirty-odd instances for two days.
