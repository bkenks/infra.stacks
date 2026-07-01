#!/usr/bin/env bash
set -euo pipefail
# Validate the compose without editing it: run `docker compose config` in a
# Linux container (has /dev/shm; macOS doesn't) after faking the runtime-only
# env files the infisical-agent renders in prod.
cd "$(dirname "$0")/.."
docker run --rm -e COMPOSE_PROJECT_NAME=woodpecker -v "$PWD":/s -w /s docker:cli sh -c '
  printf "WOODPECKER_FORGEJO_CLIENT=test\nWOODPECKER_FORGEJO_SECRET=test\nWOODPECKER_AGENT_SECRET=test\n" > /dev/shm/woodpecker.env
  docker compose config "$@"
' -- "$@"
