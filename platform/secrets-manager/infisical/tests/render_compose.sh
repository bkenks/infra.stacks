#!/usr/bin/env bash
set -euo pipefail
# Validate the compose without editing it: run `docker compose config` in a
# Linux container (has /dev/shm; macOS doesn't) after faking the runtime-only
# env files infisical needs.
cd "$(dirname "$0")/.."
docker run --rm -e COMPOSE_PROJECT_NAME=infisical \
  -v "$PWD":/s -w /s docker:cli sh -c '
  printf "INFISICAL_ENCRYPTION_KEY=test\nINFISICAL_AUTH_SECRET=test\nINFISICAL_DB_PASSWORD=test\n" > /dev/shm/platform.env
  docker compose config "$@"
' -- "$@"
