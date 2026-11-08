# Findings, 2026-11-08

## 1. Per-key guardrails need LiteLLM Enterprise

`/key/generate` with `"guardrails": ["injection-filter"]` returned 403: "This feature is only available for LiteLLM Enterprise users." The open-source edition turns a guardrail on in two ways:

| How | Who decides | Edition |
|---|---|---|
| Per request: the app sends `"guardrails": [...]` | The app, which can omit it | Open source |
| Gateway-wide: `default_on: true` in `config.yaml` | The platform team, for every call | Open source |
| Per key or team | The platform team, per app | Enterprise |

So on the open-source edition a platform team can't say "this team's key always gets the injection filter."

## 2. Budgets reserve worst-case cost before each call

At a budget of 5, the agent's main calls got 422 "Current cost: 47.149" while the key's spend was 2.40. The key record (`/key/info`) and the spend logs agreed throughout (33 calls, 25.338), so the number came from somewhere else.

Source: LiteLLM v1.106.6, `proxy/spend_tracking/budget_reservation.py`. Before sending a call, the proxy reserves its worst-case cost: input tokens plus output up to the request's `max_tokens`, capped by the model's maximum, or 16,384 tokens when unset. If budget remains, it shrinks the reservation to fit and admits the call. It refuses when open reservations already fill the budget; its "Current cost" is spent + open reservations + this request's estimate.

Hermes sends a title-generation call and its main call at once. The title call took the remaining headroom; the main call was refused.

Reproduced with no agent: on a fresh key with a budget of 5, two simultaneous calls without `max_tokens` gave one 200 and one 422 "Current cost: 66.394", with real spend 0.832.

Implication: an agent that makes parallel calls can be blocked well below its budget while dashboards show spend under budget. Set `max_tokens` on requests, or size budgets for the parallel worst case.

## 3. A gateway-wide filter screens every call

With `injection-filter` on for the whole gateway (L3), it blocked the injected note and also blocked Hermes's own title call ("list + opening message"). Every team's calls, including an agent's side calls, pass the same filter and share its false positives.

## 4. Port 4000 is taken twice

NemoClaw reserves port 4000 for its own model router (`model-router-port.ts`); LiteLLM's default port is also 4000. NemoClaw's onboarding refused the endpoint as "a protected host port". `sandbox/fwd.py` listens on 127.0.0.1:4100 and forwards to 4000; inside the sandbox, `host.openshell.internal` (192.168.5.2 under Lima) reaches the Mac's loopback.

## 5. Two key layers

The provider key stays in LiteLLM. The agent's LiteLLM virtual key stays in OpenShell, which injects it at egress; inside the sandbox the agent's environment holds only a placeholder (`opensh…`). Revoking one agent means revoking one virtual key, with no change to the provider key.
