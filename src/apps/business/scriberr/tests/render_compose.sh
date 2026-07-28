#!/usr/bin/env bash
set -euo pipefail
# Runs `docker compose config` in a Linux container. No secrets to fake — interpolation-envs supply every ${VAR:?err} the body needs.
cd "$(dirname "$0")/.."
docker run --rm -e COMPOSE_PROJECT_NAME=scriberr -v "$PWD":/s -w /s docker:cli sh -c '
  docker compose -f stack.compose.yaml config "$@"
' -- "$@"
