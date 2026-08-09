# Waking and powering off a GPU box remotely, from a dashboard tile

**Date solved:** 2026-08-08

## Symptom

Inference lives on a second machine — a workstation with a discrete GPU
("the Mothership") that idles at ~70W doing nothing. The always-on server
has no usable GPU. Leaving the workstation on 24/7 to answer occasional
prompts is wasteful; walking to it is not an option from outside the house.

Wanted: two buttons on the dashboard — wake it, shut it down — that work
from a phone on the VPN, plus enough telemetry to answer "is it on, and is
something actually using it?"

## Root cause (of why this is awkward)

- **A dashboard can't send a magic packet.** Wake-on-LAN is a raw UDP
  broadcast. Dashboards emit HTTP `href`s. Something always-on has to hold
  the trigger and translate one into the other.
- **The box can't wake itself**, so the trigger cannot live on it.
- **A dashboard link is opened by YOUR BROWSER**, not by the server. So a
  tile pointing straight at the sleeping machine arrives from a phone or a
  VPN subnet — whatever address the client happens to have — which makes a
  tight source-IP allowlist on the target impossible.

## Fix

Two small services, one on each machine, split along that last constraint.

**1. Agent on the GPU box** (`configs/mothership-agent/`) — a stdlib-only
Python HTTP service on `:9101`, a root systemd unit so it can call
`systemctl poweroff`. Exposes `/health`, `/status` (JSON), and a
token-authed `/shutdown`. Its source-IP allowlist trusts **only the
server**, which is possible precisely because nothing else ever talks to it
directly.

The GET on `/shutdown` is deliberately non-destructive — it returns a
confirm page with a POST button. Browsers, chat clients and link previewers
prefetch URLs routinely; a bare GET that kills the box would fire on hover.

**2. Responder on the always-on server** (`configs/mothership-power/`) — a
container on `:9102` that broadcasts the magic packet and **relays**
shutdown to the agent using the agent's own token, which never leaves the
server. Fronted by the existing reverse proxy behind `internal_only`.

```yaml
# network_mode: host is REQUIRED, not a shortcut -- a WoL magic packet is a
# UDP broadcast, and a bridged container's broadcast never reaches the
# wired LAN segment.
network_mode: host
```

Relaying is the whole trick: the tiles work from any client address, the
GPU box stays reachable from exactly one host, and its token never reaches
a browser.

**3. Three separate tokens.** Wake and poweroff were one shared token at
first. They are split because the wake link is the one you bookmark, paste
and leave in browser history — and it was one click from powering the box
off mid-session.

| Token | Gates | Exposure |
|---|---|---|
| `WAKE_TOKEN` | `GET /wake` | travels in a browser URL |
| `POWEROFF_TOKEN` | `GET`+`POST /shutdown` | travels in a browser URL |
| `SHUTDOWN_TOKEN` | the agent's `:9101` | server-side only, never in a browser |

**4. GPU telemetry** merged flat into the agent's `/status` from amdgpu
sysfs — `gpu_busy_percent`, `power1_average`, junction temp, VRAM, fan,
clocks. The server proxies it at `:9102/status` and passes **unknown keys
straight through**, so adding a field on the GPU box needs no change on the
server at all.

Two things that must be globbed, never hardcoded:

- The card enumerated as **`card1`**, not `card0`, and its sensors as
  `hwmon2`. Both are kernel enumeration order and move across reboots and
  kernel updates — a hardcoded path silently reports a healthy GPU as 0%.
- RDNA4 exposes **`power1_average`**; older parts only have `power1_input`.
  Try both.

## Verify

```bash
# Agent, from the server
curl -s http://<MOTHERSHIP_IP>:9101/status

# Through the relay -- this is what the dashboard actually polls
curl -s http://<LAN_IP>:9102/status
```

```json
{"status":"up","uptime":"5h 56m","gpu_busy":100,"watts":299,
 "temp_c":55,"temp_junction_c":77,"vram_pct":68,"fan_rpm":3441,
 "sclk_mhz":3309,"state":"on","model":"idle"}
```

The dashboard polls the **relay**, not the GPU box. When the machine is
asleep the relay answers `{"state":"off"}` with a 200, so the widget shows
a state instead of a dashboard API error or a tile hung on a dead host.

## Lesson

**Label telemetry by what it actually measures.** The obvious "is the GPU
busy?" signal is the inference server's model list — and it reports `idle`
while someone is gaming on the same card at 100% and 299W. That field is
labelled `Ollama`, not `GPU`, because the intuitive label would have made
the dashboard lie in the single most common case.

The general shape: when a control plane must reach a machine that is
usually off, put the trigger on the always-on host and **relay** through
it. You get one source-IP allowlist that actually holds, secrets that never
reach a browser, and graceful "it's off" instead of timeouts.
