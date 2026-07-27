#!/usr/bin/env bash
set -euo pipefail
# Runs `docker compose config` in a Linux container (for /dev/shm) after faking the
# runtime-only env files infisical needs. Covers both profiles: `server` (app/db/redis,
# needs the store's own secrets) and `agent` (renders other hosts' secrets, needs machine
# identity creds). The whole file is interpolated regardless of the active profile, so both
# credential sets are faked here.
cd "$(dirname "$0")/.."
docker run --rm -e COMPOSE_PROJECT_NAME=infisical \
  -e AGENT_HOST=test -e AGENT_SERVICES=test \
  -e INFISICAL_CLIENT_ID=test -e INFISICAL_CLIENT_SECRET=test \
  -e COMPOSE_PROFILES=server,agent \
  -e ANSIBLE_SECRETS_FILE=/dev/shm/platform.env \
  -v "$PWD":/s -w /s docker:cli sh -c '
  printf "INFISICAL_ENCRYPTION_KEY=test\nINFISICAL_AUTH_SECRET=test\nINFISICAL_DB_PASSWORD=test\n" > /dev/shm/platform.env
  docker compose config "$@"
' -- "$@"
