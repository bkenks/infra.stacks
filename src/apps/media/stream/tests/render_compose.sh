#!/usr/bin/env bash
set -euo pipefail
# Runs `docker compose config` in a Linux container (for /dev/shm) after faking the runtime-only env files infisical-agent renders in prod.
cd "$(dirname "$0")/.."
docker run --rm -e COMPOSE_PROJECT_NAME=stream -v "$PWD":/s -w /s docker:cli sh -c '
  printf "SONARR_API_KEY=test\nRADARR_API_KEY=test\n" > /dev/shm/stream.env
  docker compose -f stack.compose.yaml config "$@"
' -- "$@"
