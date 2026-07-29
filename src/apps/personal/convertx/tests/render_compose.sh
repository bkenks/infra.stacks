#!/usr/bin/env bash
set -euo pipefail
# Runs `docker compose config` in a Linux container (for /dev/shm) after faking the runtime-only env files infisical-agent renders in prod.
cd "$(dirname "$0")/.."
docker run --rm -e COMPOSE_PROJECT_NAME=convertx -v "$PWD":/s -w /s docker:cli sh -c '
  printf "CONVERTX_JWT_SECRET=test\n" > /dev/shm/convertx.env
  docker compose -f compose.yaml config "$@"
' -- "$@"
