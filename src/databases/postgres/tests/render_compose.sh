#!/usr/bin/env bash
set -euo pipefail
# Runs `docker compose config` in a Linux container (for /dev/shm) after faking the runtime-only env file postgres needs.
cd "$(dirname "$0")/.."
docker run --rm -e COMPOSE_PROJECT_NAME=postgres \
  -v "$PWD":/s -w /s docker:cli sh -c '
  printf "POSTGRES_USER=test\nPOSTGRES_PASS=test\nPG_ADMIN_PASS=test\n" > /dev/shm/postgres.env
  docker compose -f stack.compose.yaml config
  docker compose -f stack.compose.yaml --profile full config
  docker compose -f stack.compose.yaml --profile no_pgadmin config
'
