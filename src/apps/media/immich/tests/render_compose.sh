#!/usr/bin/env bash
set -euo pipefail
# Runs `docker compose config` in a Linux container. infisical-secrets fetches at `up`, not
# at `config`, so there is nothing to fake here.
cd "$(dirname "$0")/.."
docker run --rm -e COMPOSE_PROJECT_NAME=immich -v "$PWD":/s -w /s docker:cli \
  docker compose -f compose.yaml config "$@"
