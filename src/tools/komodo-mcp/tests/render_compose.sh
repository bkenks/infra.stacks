#!/usr/bin/env bash
set -euo pipefail
# Runs `docker compose config` in a Linux container (for /dev/shm) after faking the runtime-only env files infisical-agent renders in prod.
cd "$(dirname "$0")/.."
docker run --rm -e COMPOSE_PROJECT_NAME=komodo-mcp -v "$PWD":/s -w /s docker:cli sh -c '
  printf "KOMODO_API_KEY=test\nKOMODO_API_SECRET=test\nKOMODO_MCP_BASICAUTH_USERS=test:\$\$apr1\$\$test\$\$test\n" > /dev/shm/komodo-mcp.env
  docker compose config "$@"
' -- "$@"
