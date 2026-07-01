#!/usr/bin/env bash
set -euo pipefail
# Validate the compose without editing it: run `docker compose config` in a
# Linux container after faking any runtime-only env files the infisical-agent
# would render in prod. This stack has NO secrets, so there are no /dev/shm
# fakes to add — the interpolation-envs supply every ${VAR:?err} the body needs.
cd "$(dirname "$0")/.."
docker run --rm -e COMPOSE_PROJECT_NAME=scriberr -v "$PWD":/s -w /s docker:cli sh -c '
  docker compose config "$@"
' -- "$@"
