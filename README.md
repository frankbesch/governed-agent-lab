# governed-agent-lab — one AI agent, three controls, on a laptop

A Hermes agent runs inside an NVIDIA NemoClaw (OpenShell) sandbox. Every
model call leaves through the sandbox proxy, passes a LiteLLM gateway, and
is traced in Langfuse. The sandbox decides what the agent may touch, the
gateway decides which model it may call and at what cost, and tracing
records what was said and what it cost. This is a laptop lab, not a
production setup. Every result below links to its log in `results/`.

**Based on:** [research-hermes-nemoclaw-sandbox](https://github.com/frankbesch/research-hermes-nemoclaw-sandbox) for the T gates.

## Status

- **Gateway and combined gates:** 2026-11-08: C 6 of 6 and L 5 of 5 pass. [Gates and logs](docs/GATES.md).
- **Sandbox tasks:** 2026-10-20: T 4 pass, T5 not reached. [Gates](docs/GATES.md).
- **CI:** none yet.

## Measured results

One run per gate, on one macOS host with Colima.

<p align="center"><picture><source media="(prefers-color-scheme: dark)" srcset="docs/diagrams/request-dark.svg"/><img width="400" align="top" src="docs/diagrams/request-light.svg" alt="One model call: Hermes agent, OpenShell proxy, forwarder, LiteLLM gateway, NVIDIA endpoint. Text version below."/></picture> <picture><source media="(prefers-color-scheme: dark)" srcset="docs/diagrams/gates-dark.svg"/><img width="400" align="top" src="docs/diagrams/gates-light.svg" alt="Sixteen gates: 15 PASS, T5 not reached. Text version below."/></picture></p>

<details><summary>Text version of the diagram and chart</summary>

One model call: Hermes, in the sandbox, holds only a placeholder key. Its
call goes to the OpenShell proxy, which checks the host allow list and
injects the agent's virtual key; then to `fwd.py` on the host, port 4100 to
4000; then to LiteLLM (key, model access, budget, fallback, guardrails);
then to the NVIDIA endpoint, Nemotron 3 Ultra. The provider key stays in
LiteLLM. LiteLLM traces each call to Langfuse. A direct call from the
sandbox to the model is refused at the proxy with 403 (L5).

Gates, one run each, pass marks set before each run. C, the gateway with no
agent, 2026-11-08: C1 to C6 PASS. L, the sandboxed agent through the
gateway, 2026-11-08: L1 to L5 PASS. T, sandbox tasks, 2026-10-20: T1 to T4
PASS; T5 not reached, because the model refused the planted instruction
before the sandbox's controls engaged.

</details>

What the combined run adds over the separate tests: the injection probe
reached a control (the gateway blocked it before the model), cost shows per
agent task, and the gateway can't be bypassed from the sandbox.
[Interactive diagram](docs/architecture.html), built with Archify; download
it and open it in a browser.

## How it works

| Control | What it decides |
|---|---|
| Sandbox, `sandbox/` | What the agent may touch: files, hosts, programs; which key it holds |
| Gateway, `gateway/` | Which model it may call, its budget and filters, fallback when a model is down |
| Tracing, `gateway/langfuse.yml` | What it sent and received: tokens, cost, latency |

Two key layers: the provider key lives only in LiteLLM. The agent's
virtual key lives only in the OpenShell proxy, which injects it at egress.
Inside the sandbox the agent sees a placeholder.

## Quick start

- macOS with Colima or another Docker engine
- NemoClaw and OpenShell installed
- An NVIDIA API key

```bash
# 1. Then fill in every value in .env.
cd gateway && cp .env.example .env
cd ..

# 2. LiteLLM :4000, Langfuse :3000,
#    bound to 127.0.0.1.
bash gateway/up.sh

# 3. Gateway checks, then C1-C6.
python3 gateway/test_gateway.py
bash gates/run-c-gates.sh

# 4. Keep running: :4100 to :4000.
python3 -I sandbox/fwd.py

# 5. Needs sandbox/.agent-key,
#    a LiteLLM virtual key.
bash sandbox/onboard-agent.sh

# 6. L1-L5.
bash gates/run-l-gates.sh
bash gates/run-l-gates-2.sh
```

`SANDBOX`, `AGENT_KEY_ALIAS`, `COMPOSE_PROJECT`, `NVIDIA_API_KEY`, and
`NVIDIA_KEY_FILE` override the defaults. Results land in `results/<date>/`.

## Findings

Details and evidence: [docs/FINDINGS.md](docs/FINDINGS.md).

1. Per-key guardrails need LiteLLM Enterprise. The open-source edition
   supports per-request or gateway-wide guardrails only.
2. LiteLLM reserves each call's worst-case cost before sending it. An agent
   that makes parallel calls can get a 422 below its budget unless requests
   set `max_tokens`.
3. A gateway-wide filter screens every call an agent makes, including its
   side calls, and shares their false positives.
4. NemoClaw reserves port 4000 for its own model router, LiteLLM's default
   port. `sandbox/fwd.py` bridges 4100 to 4000.

## Known gaps

- Synthetic prompts on a laptop. Not production, not hardened, not a
  security claim.
- Prices in `gateway/config.yaml` are made up so spend tracking shows.
  Don't quote them.
- One run per gate. NemoClaw is alpha software.
- Not shown: GPU scheduling, Kubernetes operations, fleet management,
  observability platforms.
- LiteLLM is pinned to v1.106.6. LiteLLM has had serious security
  advisories; check them before reusing this setup.

## More

- [Gates, pass marks, and results](docs/GATES.md).
- [Findings and evidence](docs/FINDINGS.md).
- [Interactive diagram](docs/architecture.html) (Archify, Quoin colours).
- README pictures: `docs/diagrams/charts.py`.
- Built with an AI coding agent under my direction. The agent ran the
  2026-11-08 gates; I review and re-run a gate before citing it.

## License

No license is granted yet; all rights reserved.

**Last measured**: 2026-11-08. See [results/2026-11-08/](results/2026-11-08/).
