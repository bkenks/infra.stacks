#!/usr/bin/env bash
set -euo pipefail
# Validate the compose without editing it: run `docker compose config` in a
# Linux container (has /dev/shm; macOS doesn't) after faking the runtime-only
# env files the infisical-agent renders in prod.
cd "$(dirname "$0")/.."
docker run --rm -e COMPOSE_PROJECT_NAME=twenty -v "$PWD":/s -w /s docker:cli sh -c '
  printf "TWENTY_SECRET=test\nTWENTY_GOOGLE_CLIENT_ID=test\nTWENTY_GOOGLE_CLIENT_SECRET=test\n" > /dev/shm/twenty.env
  printf "POSTGRES_USER=test\nPOSTGRES_PASS=test\n" > /dev/shm/postgres.env
  docker compose config "$@"
' -- "$@"
