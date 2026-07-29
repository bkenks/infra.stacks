#!/usr/bin/env bash
set -euo pipefail
# Runs `docker compose config` in a Linux container (for /dev/shm) after faking the runtime-only env files infisical-agent renders in prod.
cd "$(dirname "$0")/.."
docker run --rm -e COMPOSE_PROJECT_NAME=woodpecker -v "$PWD":/s -w /s docker:cli sh -c '
  printf "WOODPECKER_FORGEJO_CLIENT=test\nWOODPECKER_FORGEJO_SECRET=test\nWOODPECKER_AGENT_SECRET=test\n" > /dev/shm/woodpecker.env
  docker compose -f compose.yaml config "$@"
' -- "$@"
