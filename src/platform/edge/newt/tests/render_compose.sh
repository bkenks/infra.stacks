#!/usr/bin/env bash
set -euo pipefail
# Runs `docker compose config` in a Linux container (for /dev/shm) after faking the runtime-only env file infisical-agent renders in prod (/dev/shm/newt.env).
cd "$(dirname "$0")/.."
docker run --rm -e COMPOSE_PROJECT_NAME=newt -v "$PWD":/s -w /s docker:cli sh -c '
  printf "NEWT_ID=test\nNEWT_SECRET=test\n" > /dev/shm/newt.env
  docker compose config "$@"
' -- "$@"
