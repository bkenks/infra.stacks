#!/usr/bin/env bash
set -euo pipefail
# Validate the compose without editing it: run `docker compose config` in a
# Linux container (has /dev/shm; macOS doesn't) after faking the runtime-only
# env files the infisical-agent renders in prod. Uncomment / add one printf line
# per fake file the stack needs — match the /dev/shm paths in compose.yaml, and
# put any ${VAR:?err} interpolation values the body expects inside it.
cd "$(dirname "$0")/.."
docker run --rm -e COMPOSE_PROJECT_NAME=infisical \
  -e AGENT_HOST=test -e AGENT_SERVICES=test \
  -e INFISICAL_CLIENT_ID=test -e INFISICAL_CLIENT_SECRET=test \
  -v "$PWD":/s -w /s docker:cli sh -c '
  printf "INFISICAL_CLIENT_ID=test\nINFISICAL_CLIENT_SECRET=test\n" > /dev/shm/platform.env
  docker compose config "$@"
' -- "$@"
