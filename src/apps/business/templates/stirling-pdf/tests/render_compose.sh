#!/usr/bin/env bash
set -euo pipefail
# Runs `docker compose config` in a Linux container (for /dev/shm). No secrets to fake for this stack.
cd "$(dirname "$0")/.."
docker run --rm -e COMPOSE_PROJECT_NAME=stirling-pdf -v "$PWD":/s -w /s docker:cli sh -c '
  docker compose -f compose.yaml config "$@"
' -- "$@"
