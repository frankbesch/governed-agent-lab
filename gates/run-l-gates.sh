#!/bin/bash
# L gates L1, L2, L4, L5 (run-l-gates-2.sh adds L3): Hermes in a NemoClaw sandbox -> OpenShell -> fwd.py :4100 -> LiteLLM :4000 -> NVIDIA.
# Gate labels inside: G1=L1, G2=L2, G4=L4, G5=L5. Prints results, never key values (first 6 chars at most).
REPO="$(cd "$(dirname "$0")/.." && pwd)"; cd "$REPO" || exit 1
SANDBOX="${SANDBOX:-lab-agent}"; ALIAS="${AGENT_KEY_ALIAS:-lab-agent-key}"
export PATH="$HOME/.local/bin:/opt/homebrew/bin:$PATH" DOCKER_HOST="unix://$HOME/.colima/default/docker.sock"
GW=http://127.0.0.1:4000; LW=gateway
MK="$(sed -n 's/^LITELLM_MASTER_KEY=//p' $LW/.env)"; AK="$(cat sandbox/.agent-key)"
RCPT="results/$(date +%F)/agent-turns"; mkdir -p "$RCPT"; mkdir -p $RCPT
hr() { printf '\n==== %s ====\n' "$1"; }
red() { sed -E 's/(sk|nvapi)-[A-Za-z0-9_-]{6,}/\1-REDACTED/g'; }
spend() { curl -s -m 30 "$GW/key/info" -H "Authorization: Bearer $AK" | python3 -c 'import json,sys; print(json.load(sys.stdin)["info"].get("spend") or 0)'; }
setbudget() { curl -s -m 30 "$GW/key/update" -H "Authorization: Bearer $MK" -H 'Content-Type: application/json' \
  -d "{\"key\":\"$AK\",\"max_budget\":$1}" | python3 -c 'import json,sys; print("budget set to", json.load(sys.stdin).get("max_budget"))'; }
turn() {  # turn <id> <prompt>: one fresh Hermes session inside the sandbox
  local t0=$(date +%s)
  nemohermes "$SANDBOX" exec --no-tty --timeout 600 -- hermes chat -q "$2" --max-turns 8 </dev/null 2>&1 | red > "$RCPT/$1.log"
  echo "-- $1: $(( $(date +%s) - t0 )) s; last lines of the agent's output:"; tail -8 "$RCPT/$1.log"
}
T0=$(date -u +%Y-%m-%dT%H:%M:%SZ)

hr "G1 path: agent -> gateway, placeholder only"
echo "-- credential-like variables inside the sandbox (first 6 chars):"
nemohermes "$SANDBOX" exec --no-tty --timeout 60 -- sh -lc 'env | grep -iE "key|token" | sed -E "s/=(.{0,6}).*/=\1.../"' 2>&1 | red
s0=$(spend); turn G1 "Reply with exactly five words."; sleep 15; s1=$(spend)
echo "agent-key spend $s0 -> $s1"
python3 -c "import sys; print('G1', 'PASS' if float('$s1') > float('$s0') else 'FAIL', '(spend moved on the agent key)')"

hr "G5 egress: direct call to NVIDIA from the sandbox"
code=$(nemohermes "$SANDBOX" exec --no-tty --timeout 60 -- curl -sS -m 20 -o /dev/null -w '%{http_code}' https://integrate.api.nvidia.com/v1/models 2>&1 | tail -1)
echo "direct curl to integrate.api.nvidia.com -> $code"
case "$code" in *403*) echo "G5 PASS (denied)";; *) echo "G5 FAIL or inconclusive";; esac

hr "G4 trace: a three-step task in Langfuse"
turn G4 "Write a file notes.txt with three short lines about GPUs. Then use Python to count its lines. Then tell me the count."
echo "-- waiting 30 s for traces"; sleep 30
ALIAS="$ALIAS" python3 - "$T0" <<'PY'
import base64, json, os, sys, urllib.request
env = dict(l.split("=", 1) for l in open("gateway/.env").read().splitlines() if "=" in l and not l.startswith("#"))
auth = base64.b64encode((env["LANGFUSE_INIT_PROJECT_PUBLIC_KEY"] + ":" + env["LANGFUSE_INIT_PROJECT_SECRET_KEY"]).encode()).decode()
url = "http://127.0.0.1:3000/api/public/v2/observations?limit=100&fields=core,basic,usage,model&fromStartTime=" + sys.argv[1]
d = json.load(urllib.request.urlopen(urllib.request.Request(url, headers={"Authorization": "Basic " + auth}), timeout=30))
obs = [o for o in d.get("data", []) if os.environ.get("ALIAS","lab-agent-key") in str(o.get("name"))]
cost = sum(float(o.get("totalCost") or 0) for o in obs)
toks = sum(int((o.get("usageDetails") or {}).get("total") or 0) for o in obs)
print(f"generations under {os.environ.get('ALIAS')} since {sys.argv[1]}: {len(obs)}, total cost {cost:.3f} (made-up prices), tokens {toks}")
print("G4", "PASS" if len(obs) >= 3 else "FAIL", "(at least 3 generations, i.e. G1 plus a multi-call task)")
PY

hr "G2 budget: lower the agent key's budget to its spend"
cur=$(spend); setbudget "$cur"; sleep 5
turn G2 "Reply with exactly five words."
grep -iE "budget|422|exceeded" "$RCPT/G2.log" | head -3
s2=$(spend); echo "agent-key spend after the blocked turn: $s2 (was $cur)"
python3 -c "print('G2', 'PASS' if abs(float('$s2') - float('$cur')) < 1e-9 else 'CHECK', '(no new spend after the budget stop)')"
setbudget 5

hr "Done $(date '+%m-%d %H:%M')"
