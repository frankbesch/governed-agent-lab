#!/bin/bash
# Start the gateway stack (LiteLLM + Langfuse). The NVIDIA key comes from $NVIDIA_API_KEY or the file $NVIDIA_KEY_FILE
# (default ~/.hermes/.env), into this process only; never printed or stored.
cd "$(dirname "$0")" || exit 1
export PATH="/opt/homebrew/bin:$PATH"
export DOCKER_HOST="${DOCKER_HOST:-unix://$HOME/.colima/default/docker.sock}"
NVIDIA_NIM_API_KEY="${NVIDIA_API_KEY:-$(sed -n 's/^NVIDIA_API_KEY=//p' "${NVIDIA_KEY_FILE:-$HOME/.hermes/.env}" 2>/dev/null | tr -d '\r"' | head -n1)}"
export NVIDIA_NIM_API_KEY
docker-compose -p ${COMPOSE_PROJECT:-prep} -f langfuse.yml -f litellm.yml up -d 2>&1 | tail -4 | cut -c1-100
unset NVIDIA_NIM_API_KEY
for i in $(seq 1 36); do
  a=$(curl -s -m 3 -o /dev/null -w '%{http_code}' http://127.0.0.1:4000/health/readiness)
  b=$(curl -s -m 3 -o /dev/null -w '%{http_code}' http://127.0.0.1:3000/api/public/health)
  [ "$a" = 200 ] && [ "$b" = 200 ] && break
  sleep 10
done
echo "litellm readiness=$a langfuse health=$b"
docker-compose -p ${COMPOSE_PROJECT:-prep} -f langfuse.yml -f litellm.yml ps --format '{{.Service}} {{.Status}}' 2>/dev/null | cut -c1-70
