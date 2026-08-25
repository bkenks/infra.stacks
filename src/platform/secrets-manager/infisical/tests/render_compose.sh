#!/usr/bin/env bash
set -euo pipefail
# Runs `docker compose config` in a Linux container (for /dev/shm) after faking the env file
# the control plane writes. This is the one stack still on an env file: the infisical-secrets
# provider cannot fetch this server's own secrets from it before it is up.
cd "$(dirname "$0")/.."
docker run --rm -e COMPOSE_PROJECT_NAME=infisical \
  -e ANSIBLE_SECRETS_FILE=/dev/shm/platform.env \
  -v "$PWD":/s -w /s docker:cli sh -c '
  printf "INFISICAL_ENCRYPTION_KEY=test\nINFISICAL_AUTH_SECRET=test\nINFISICAL_DB_PASSWORD=test\n" > /dev/shm/platform.env
  docker compose -f compose.yaml config "$@"
' -- "$@"
