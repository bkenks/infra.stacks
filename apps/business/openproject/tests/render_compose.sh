#!/usr/bin/env bash
set -euo pipefail
# Validate the compose without editing it: run `docker compose config` in a
# Linux container (has /dev/shm; macOS doesn't) after faking the runtime-only
# env files the infisical-agent renders in prod. Add a line to fake more files.
cd "$(dirname "$0")/.."
docker run --rm -e COMPOSE_PROJECT_NAME=openproject -v "$PWD":/s -w /s docker:cli sh -c '
  printf "POSTGRES_USER=test\nPOSTGRES_PASS=test\n"            > /dev/shm/postgres.env
  printf "OPEN_PRJ_SECRET_KEY=test\nCOLLAB_SERVER_SECRET=test\n" > /dev/shm/openproject.env
  docker compose config "$@"
' -- "$@"
