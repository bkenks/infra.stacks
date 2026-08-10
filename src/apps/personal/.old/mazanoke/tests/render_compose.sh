#!/usr/bin/env bash
set -euo pipefail
# Runs `docker compose config` in a Linux container (for /dev/shm). No secrets for this stack.
cd "$(dirname "$0")/.."
docker run --rm -e COMPOSE_PROJECT_NAME=mazanoke -v "$PWD":/s -w /s docker:cli sh -c '
  docker compose -f compose.yaml config "$@"
' -- "$@"
