#!/usr/bin/env bash
set -euo pipefail
# Runs `docker compose config` in a Linux container (for /dev/shm) after faking the runtime-only env files infisical-agent renders in prod.
cd "$(dirname "$0")/.."
docker run --rm -e COMPOSE_PROJECT_NAME=openproject -v "$PWD":/s -w /s docker:cli sh -c '
  printf "OPEN_PRJ_SECRET_KEY=test\nCOLLAB_SERVER_SECRET=test\n" > /dev/shm/openproject.env
  printf "POSTGRES_USER=test\nPOSTGRES_PASS=test\n" > /dev/shm/postgres.env
  docker compose -f stack.compose.yaml config "$@"
' -- "$@"
