#!/usr/bin/env bash
set -euo pipefail
# Validate the compose without editing it: run `docker compose config` in a
# Linux container (has /dev/shm; macOS doesn't) after faking the runtime-only
# env file postgres needs.
cd "$(dirname "$0")/.."
docker run --rm -e COMPOSE_PROJECT_NAME=postgres \
  -v "$PWD":/s -w /s docker:cli sh -c '
  printf "POSTGRES_USER=test\nPOSTGRES_PASS=test\nPG_ADMIN_PASS=test\n" > /dev/shm/postgres.env
  docker compose config
  docker compose --profile full config
  docker compose --profile no_pgadmin config
'
