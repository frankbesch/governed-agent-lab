#!/bin/bash
# Reload config.yaml by recreating only the LiteLLM container. Reads the NVIDIA key into this process only; never prints or stores it.
cd "$(dirname "$0")" || exit 1
export PATH="/opt/homebrew/bin:$PATH"
export DOCKER_HOST="${DOCKER_HOST:-unix://$HOME/.colima/default/docker.sock}"
NVIDIA_NIM_API_KEY="${NVIDIA_API_KEY:-$(sed -n 's/^NVIDIA_API_KEY=//p' "${NVIDIA_KEY_FILE:-$HOME/.hermes/.env}" 2>/dev/null | tr -d '\r"' | head -n1)}"
export NVIDIA_NIM_API_KEY
docker-compose -p ${COMPOSE_PROJECT:-prep} -f langfuse.yml -f litellm.yml up -d --no-deps --force-recreate litellm 2>&1 | tail -1 | cut -c1-80
unset NVIDIA_NIM_API_KEY
for i in $(seq 1 24); do
  a=$(curl -s -m 3 -o /dev/null -w '%{http_code}' http://127.0.0.1:4000/health/readiness)
  [ "$a" = 200 ] && break
  sleep 5
done
echo "litellm readiness=$a"
