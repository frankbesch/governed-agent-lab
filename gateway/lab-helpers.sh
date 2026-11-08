# Helpers for the C gates. Load with: source gateway/lab-helpers.sh
# Synthetic prompts only. Prices in config.yaml are made up. Prints key aliases and results, never key values.
LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
GW="http://127.0.0.1:4000"
MK="$(sed -n 's/^LITELLM_MASTER_KEY=//p' "$LAB_DIR/.env")"

# newkey <alias> <budget> <model> [model...]: prints a new virtual key; capture it with KEY=$(newkey ...)
newkey() {
  local alias="$1" budget="$2"; shift 2
  local models; models="$(printf '"%s",' "$@")"; models="[${models%,}]"
  curl -s -m 30 "$GW/key/generate" \
    -H "Authorization: Bearer $MK" -H 'Content-Type: application/json' \
    -d "{\"key_alias\":\"$alias-$(date +%s)\",\"models\":$models,\"max_budget\":$budget}" \
    | python3 -c 'import json,sys; print(json.load(sys.stdin)["key"])'
}

# chat <key or "none"> <model> [max_tokens] [guardrail] [prompt]: one call, then status, model, tokens, reply, fallbacks, cost
chat() {
  # Default 1000: on 11-06 this model spent all of a 400-token limit on reasoning in 2 of 4 calls.
  local key="$1" model="$2" max="${3:-1000}" guard="${4:-}" prompt="${5:-Reply with exactly five words.}"
  local auth=(); [ "$key" != none ] && auth=(-H "Authorization: Bearer $key")
  CHAT_MODEL="$model" CHAT_MAX="$max" CHAT_GUARD="$guard" CHAT_PROMPT="$prompt" python3 -c '
import json, os
b = {"model": os.environ["CHAT_MODEL"], "max_tokens": int(os.environ["CHAT_MAX"]),
     "messages": [{"role": "user", "content": os.environ["CHAT_PROMPT"]}]}
if os.environ["CHAT_GUARD"]:
    b["guardrails"] = [os.environ["CHAT_GUARD"]]
print(json.dumps(b))' > /tmp/lab-req.json
  local code
  code="$(curl -s -m 120 -D /tmp/lab-h.txt -o /tmp/lab-r.json -w '%{http_code}' "$GW/v1/chat/completions" \
    "${auth[@]}" -H 'Content-Type: application/json' -d @/tmp/lab-req.json)"
  echo "HTTP $code"
  python3 - <<'PY'
import json
b = json.load(open("/tmp/lab-r.json"))
if "error" in b:
    e = b["error"]
    print("error type:", e.get("type"), "| code:", e.get("code"))
    print("message:", str(e.get("message"))[:160])
else:
    u = b.get("usage") or {}
    d = u.get("completion_tokens_details") or {}
    c = (b["choices"][0]["message"].get("content") or "")
    print("model:", b.get("model"))
    print("tokens: input", u.get("prompt_tokens"), "| output", u.get("completion_tokens"), "| reasoning", d.get("reasoning_tokens"))
    print("finish_reason:", b["choices"][0].get("finish_reason"))
    print("reply:", repr(c[:120]))
PY
  grep -i -E '^x-litellm-(attempted-fallbacks|model-group|response-cost):' /tmp/lab-h.txt | tr -d '\r'
  rm -f /tmp/lab-req.json /tmp/lab-r.json /tmp/lab-h.txt
}

# spend <key>: spend recorded against a key. Recording lags a few seconds.
spend() {
  curl -s -m 30 "$GW/key/info" -H "Authorization: Bearer $1" \
    | python3 -c 'import json,sys; i=json.load(sys.stdin)["info"]; print("spend", i.get("spend"), "of budget", i.get("max_budget"), "| models", i.get("models"))'
}
