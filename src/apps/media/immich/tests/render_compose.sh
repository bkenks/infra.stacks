#!/usr/bin/env bash
set -euo pipefail
# Runs `docker compose config` in a Linux container (for /dev/shm) after faking the runtime-only env file infisical-agent renders in prod.
cd "$(dirname "$0")/.."
docker run --rm -e COMPOSE_PROJECT_NAME=immich -v "$PWD":/s -w /s docker:cli sh -c '
  printf "IMMICH_DB_PASSWORD=test\n" > /dev/shm/immich.env
  docker compose -f stack.compose.yaml config "$@"
' -- "$@"
