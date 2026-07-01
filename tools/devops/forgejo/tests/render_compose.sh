#!/usr/bin/env bash
set -euo pipefail
# Validate the compose without editing it: run `docker compose config` in a
# Linux container (has /dev/shm; macOS doesn't) after faking the runtime-only
# env files the infisical-agent renders in prod.
cd "$(dirname "$0")/.."
docker run --rm -e COMPOSE_PROJECT_NAME=forgejo -v "$PWD":/s -w /s docker:cli sh -c '
  printf "DB_PASSWORD=test\n" > /dev/shm/forgejo.env
  docker compose config "$@"
' -- "$@"
