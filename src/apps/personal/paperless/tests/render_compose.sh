#!/usr/bin/env bash
set -euo pipefail
# Runs `docker compose config` in a Linux container (for /dev/shm) after faking the runtime-only env files infisical-agent renders in prod.
cd "$(dirname "$0")/.."
docker run --rm -e COMPOSE_PROJECT_NAME=paperless -v "$PWD":/s -w /s docker:cli sh -c '
  printf "PAPERLESS_SECRET_KEY=test\nPAPERLESS_PG_PASS=test\n" > /dev/shm/paperless.env
  docker compose -f compose.yaml config "$@"
' -- "$@"
