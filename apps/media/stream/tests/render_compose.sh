#!/usr/bin/env bash
set -euo pipefail
# Validate the compose without editing it: run `docker compose config` in a
# Linux container (has /dev/shm; macOS doesn't) after faking the runtime-only
# env files the infisical-agent renders in prod.
cd "$(dirname "$0")/.."
docker run --rm -e COMPOSE_PROJECT_NAME=stream -v "$PWD":/s -w /s docker:cli sh -c '
  printf "SONARR_API_KEY=test\nRADARR_API_KEY=test\n" > /dev/shm/stream.env
  docker compose config "$@"
' -- "$@"
