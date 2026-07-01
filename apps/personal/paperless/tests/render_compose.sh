#!/usr/bin/env bash
set -euo pipefail
# Validate the compose without editing it: run `docker compose config` in a
# Linux container (has /dev/shm; macOS doesn't) after faking the runtime-only
# env files the infisical-agent renders in prod.
cd "$(dirname "$0")/.."
docker run --rm -e COMPOSE_PROJECT_NAME=paperless -v "$PWD":/s -w /s docker:cli sh -c '
  printf "PAPERLESS_SECRET_KEY=test\nPAPERLESS_PG_PASS=test\n" > /dev/shm/paperless.env
  docker compose config "$@"
' -- "$@"
