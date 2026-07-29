#!/usr/bin/env bash
set -euo pipefail
# Runs `docker compose config` in a Linux container (for /dev/shm) after faking the runtime-only env files infisical-agent renders in prod.
# HTTP_SCHEME/KOMODO_FQDN are not secrets — Komodo supplies them from the stack's `environment` block in komodo-config-sync.toml.
cd "$(dirname "$0")/.."
docker run --rm -e COMPOSE_PROJECT_NAME=komodo-mcp -e HTTP_SCHEME=http -e KOMODO_FQDN=10.100.0.21:9120 -v "$PWD":/s -w /s docker:cli sh -c '
  printf "KOMODO_API_KEY=test\nKOMODO_API_SECRET=test\nKOMODO_MCP_BASICAUTH_USERS=test:\$\$apr1\$\$test\$\$test\n" > /dev/shm/komodo-mcp.env
  docker compose -f compose.yaml config "$@"
' -- "$@"
