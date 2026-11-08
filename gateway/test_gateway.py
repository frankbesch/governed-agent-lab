#!/usr/bin/env python3
"""Local LiteLLM and Langfuse checks. Synthetic prompts only. Prints key aliases, never key values."""
import base64, json, os, time, urllib.error, urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ENV = dict(l.strip().split("=", 1) for l in open(os.path.join(HERE, ".env")) if "=" in l and not l.startswith("#"))
GW, LF = "http://127.0.0.1:4000", "http://127.0.0.1:3000"
MASTER = ENV["LITELLM_MASTER_KEY"]
RUN = str(int(time.time()))
PASS = []


def call(method, url, key=None, body=None, basic=None):
    h = {"Content-Type": "application/json"}
    if key:
        h["Authorization"] = "Bearer " + key
    if basic:
        h["Authorization"] = "Basic " + base64.b64encode(basic.encode()).decode()
    req = urllib.request.Request(url, method=method, headers=h, data=json.dumps(body).encode() if body else None)
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            return r.status, dict(r.headers), json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        raw = e.read()
        try:
            return e.code, dict(e.headers), json.loads(raw)
        except ValueError:
            return e.code, dict(e.headers), {"raw": raw[:200].decode("utf-8", "replace")}


def hdr(h, name):
    return {k.lower(): v for k, v in h.items()}.get(name)


def check(gate, ok, detail):
    PASS.append(ok)
    print(f"{'PASS' if ok else 'FAIL'} {gate}: {detail}")


def chat(key, model, tag):
    return call("POST", GW + "/v1/chat/completions", key, {
        # 400 made G3 flaky: on 11-06 reasoning used the whole limit in 2 of 4 calls, leaving an empty reply.
        "model": model, "max_tokens": 1000,
        "messages": [{"role": "user", "content": f"Synthetic test {tag}-{RUN}: reply with exactly five words."}],
    })


def newkey(alias, **kw):
    s, _, b = call("POST", GW + "/key/generate", MASTER, {"key_alias": f"{alias}-{RUN}", **kw})
    if s != 200:
        raise SystemExit(f"key generation failed for {alias}: {s}")
    return b["key"]


def spend(key):
    s, _, b = call("GET", GW + "/key/info", key)
    return round((b.get("info") or {}).get("spend") or 0, 6)


s, _, _ = call("GET", GW + "/health/readiness")
check("G1 gateway ready", s == 200, f"status {s}")

s, _, b = call("POST", GW + "/v1/chat/completions", None, {"model": "nemotron", "messages": [{"role": "user", "content": "x"}]})
check("G2 no key is refused", s == 401, f"status {s}")

team = newkey("team-a", models=["nemotron", "broken-primary"], max_budget=100)
limited = newkey("limited", models=["nemotron"], max_budget=100)
small = newkey("small-budget", models=["nemotron"], max_budget=0.01)

before = spend(team)
s, h, b = chat(team, "nemotron", "route")
u = b.get("usage") or {}
cost = hdr(h, "x-litellm-response-cost")
reply = ((b.get("choices") or [{}])[0].get("message") or {}).get("content")
check("G3 virtual key reaches the model in OpenAI format", s == 200 and bool(b.get("id")) and bool(u) and bool(reply),
      f"status {s}, object {b.get('object')}, model {b.get('model')}, usage {u.get('prompt_tokens')}+{u.get('completion_tokens')}, reply {str(reply)[:50]!r}")
check("G4 cost header present", cost not in (None, "0", "0.0"), f"x-litellm-response-cost {cost} (made-up prices)")

s, h, b = chat(team, "broken-primary", "fallback")
fb = hdr(h, "x-litellm-attempted-fallbacks")
check("G5 dead endpoint falls back", s == 200 and fb not in (None, "0"), f"status {s}, attempted fallbacks {fb}, model group {hdr(h, 'x-litellm-model-group')}")

s, _, b = chat(limited, "broken-primary", "denied")
check("G6 key can't use a model it wasn't given", s in (401, 403), f"status {s}, {str((b.get('error') or {}).get('type'))}")

after = before
for _ in range(14):
    after = spend(team)
    if after > before:
        break
    time.sleep(10)
check("G7 spend recorded against the key", after > before, f"team-a spend {before} to {after}")

s, _, _ = chat(small, "nemotron", "budget-1")
first = s
last = None
for i in range(14):
    time.sleep(10)
    s, _, b = chat(small, "nemotron", f"budget-{i+2}")
    last = (s, str((b.get("error") or {}).get("type")), str((b.get("error") or {}).get("message"))[:70])
    if s != 200:
        break
check("G8 budget stops the key", first == 200 and last and last[0] != 200, f"first {first}, then {last}")

# Langfuse v4 removed /api/public/traces in events_only mode; v2 observations is the supported read path.
auth = ENV["LANGFUSE_INIT_PROJECT_PUBLIC_KEY"] + ":" + ENV["LANGFUSE_INIT_PROJECT_SECRET_KEY"]
hits = []
for _ in range(18):
    s, _, b = call("GET", LF + "/api/public/v2/observations?limit=30&fields=core,basic,usage,io,model", basic=auth)
    hits = [o for o in (b.get("data") or []) if RUN in json.dumps(o.get("input"))]
    if s == 200 and len(hits) >= 3:
        break
    time.sleep(10)
check("G9 traces reach Langfuse", len(hits) >= 3, f"{len(hits)} generations from this run")
if hits:
    o = hits[-1]
    check("G10 trace holds the prompt, reply, and usage", bool(o.get("input")) and bool(o.get("output")) and bool(o.get("usageDetails")),
          f"name {o.get('name')}, model {o.get('model')}, latency {o.get('latency')}, cost {o.get('totalCost')}, tokens {(o.get('usageDetails') or {}).get('total')}")
    print("  note: the gateway logged the full prompt and reply, so sensitive text needs a redaction decision.")

print(f"\nRESULT {sum(PASS)} of {len(PASS)} passed, run {RUN}")
