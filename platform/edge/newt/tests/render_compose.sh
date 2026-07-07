#!/usr/bin/env bash
set -euo pipefail
# Validate the compose without editing it: run `docker compose config` in a
# Linux container (has /dev/shm; macOS doesn't) after faking the runtime-only
# env file the infisical-agent renders in prod (/dev/shm/newt.env).
cd "$(dirname "$0")/.."
docker run --rm -e COMPOSE_PROJECT_NAME=newt -v "$PWD":/s -w /s docker:cli sh -c '
  printf "NEWT_ID=test\nNEWT_SECRET=test\n" > /dev/shm/newt.env
  docker compose config "$@"
' -- "$@"
