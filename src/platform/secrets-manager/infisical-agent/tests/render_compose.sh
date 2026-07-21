#!/usr/bin/env bash
set -euo pipefail
# Runs `docker compose config` in a Linux container (for /dev/shm). Add one printf line per fake file needed, matching the /dev/shm paths in compose.yaml.
cd "$(dirname "$0")/.."
docker run --rm -e COMPOSE_PROJECT_NAME=infisical \
  -e AGENT_HOST=test -e AGENT_SERVICES=test \
  -e INFISICAL_CLIENT_ID=test -e INFISICAL_CLIENT_SECRET=test \
  -v "$PWD":/s -w /s docker:cli sh -c '
  printf "INFISICAL_CLIENT_ID=test\nINFISICAL_CLIENT_SECRET=test\n" > /dev/shm/platform.env
  docker compose config "$@"
' -- "$@"
