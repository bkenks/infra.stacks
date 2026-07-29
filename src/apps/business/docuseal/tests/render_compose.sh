#!/usr/bin/env bash
set -euo pipefail
# Runs `docker compose config` in a Linux container (for /dev/shm) after faking the runtime-only env files infisical-agent renders in prod.
cd "$(dirname "$0")/.."
docker run --rm -e COMPOSE_PROJECT_NAME=docuseal -v "$PWD":/s -w /s docker:cli sh -c '
  printf "DOCUSEAL_SECRET_KEY_BASE=test\n" > /dev/shm/docuseal.env
  printf "POSTGRES_USER=test\nPOSTGRES_PASS=test\n" > /dev/shm/postgres.env
  docker compose -f compose.yaml config "$@"
' -- "$@"
