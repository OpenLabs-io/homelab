# A status page that lied for five minutes: mixed content killed the poll

**Date solved:** 2026-08-08

## Symptom

Clicking the "Wake" dashboard tile opened a page that said *"Magic packet
sent — waiting for the machine to boot…"* with a spinner, and then, five
minutes later:

> No response after 5 minutes — check it manually.

The machine had booted in about thirty seconds. It was up, reachable and
serving. The page just never noticed — every single time.

## Root cause

The page polled the target's health endpoint from JavaScript:

```js
await fetch('http://<MOTHERSHIP_IP>:9101/health', {mode:'no-cors'});
```

The page itself is served over **HTTPS** through the reverse proxy. A
`fetch()` from an `https://` page to an `http://` URL is **mixed active
content**, which every current browser blocks outright. `mode:'no-cors'`
does not exempt it — that option relaxes CORS, and this never reaches CORS.

So the request died in the browser before a packet left the machine. And
the failure was invisible because the poll's error path swallowed it:

```js
} catch (e) {}          // <- the block landed here, silently, forever
```

The loop then ran its full five-minute budget and reported the timeout
message it was designed to show for a machine that genuinely failed to
boot. Two ordinary decisions — serve the dashboard over HTTPS, ignore
errors in a retry loop — combined into a page that confidently reported the
opposite of the truth.

It only worked when hit directly on the LAN over plain HTTP, which is
exactly how it got tested.

## Fix

Move the cross-origin hop **server-side**, where mixed-content rules do not
exist, and give the page a same-origin relative path to poll.

```python
# New route on the responder
if url.path == "/target-health":
    if not self._source_ok("/target-health"):
        return
    up = target_up()          # server-side GET, 3s timeout
    return self._send(200 if up else 503, "up" if up else "down",
                      "text/plain; charset=utf-8")
```

```js
// Relative path on purpose. An absolute http:// URL here is mixed
// content and the browser kills it silently.
const r = await fetch('/target-health', {cache:'no-store'});
if (r.ok) { /* it's up */ }
```

Bound the server-side probe (3s here). When the target is powered off the
connect is an ARP failure, not a refusal, so an unbounded probe would pin a
thread per poll.

## Verify

```bash
# Through the proxy -- the path the tile actually uses
curl -sk -o /dev/null -w '%{http_code}\n' https://<host>/target-health   # 200

# And confirm the page emits a RELATIVE url
curl -sk 'https://<host>/wake?token=…' | grep -o "fetch([^)]*)"
# fetch('/target-health', {cache:'no-store'})
```

## Lesson

**An empty `catch` turns a browser security policy into a phantom hardware
fault.** The page reported "the machine didn't boot" when the truth was
"your browser refused to ask." Log the exception, or at minimum distinguish
"probe failed" from "probe says down" — they are different states and only
one of them is about the thing you're monitoring.

Second: **test over the transport users actually use.** This worked
perfectly on `http://IP:port` during development and was broken 100% of the
time through the HTTPS name in the dashboard. Any page served over TLS
cannot fetch, XHR, or open a WebSocket to a plain-HTTP origin — if a
service is behind a proxy, everything it talks to from the browser must be
same-origin or HTTPS too.
