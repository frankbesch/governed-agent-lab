#!/bin/bash
# Onboard a Hermes sandbox whose only inference route is the LiteLLM gateway, reached through fwd.py on localhost:4100.
# The agent's virtual key is read from sandbox/.agent-key (0600, gitignored) and never printed.
# NemoClaw docs: inference/set-up-openai-compatible-endpoint.mdx and custom-endpoint-security.mdx
cd "$(dirname "$0")"
export NEMOCLAW_PROVIDER=custom
export NEMOCLAW_ENDPOINT_URL=http://localhost:4100/v1
export NEMOCLAW_MODEL=nemotron
export NEMOCLAW_VLLM_PORT=4100   # 4000 is the reserved NemoClaw Model Router port; fwd.py forwards 4100 to LiteLLM on 4000
export NEMOCLAW_POLICY_MODE=suggested
export NEMOCLAW_DISABLE_TELEMETRY=1
COMPATIBLE_API_KEY="$(cat .agent-key)"; export COMPATIBLE_API_KEY
nemohermes onboard --agent hermes --name "${SANDBOX:-lab-agent}" --non-interactive --fresh --yes --yes-i-accept-third-party-software --no-gpu
echo "onboard exit: $?"
