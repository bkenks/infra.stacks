#!/usr/bin/env bash
set -euo pipefail
# Runs `docker compose config` in a Linux container (for /dev/shm) after faking the runtime-only env file infisical-agent renders in prod, and the host bind-mount dir `init` would otherwise create.
cd "$(dirname "$0")/.."
docker run --rm -e COMPOSE_PROJECT_NAME=pangolin -v "$PWD":/s -w /s docker:cli sh -c '
  printf "SERVER_SECRET=test\nEMAIL_SMTP_PASS=test\n" > /dev/shm/pangolin.env
  printf "CF_DNS_API_TOKEN=test\n" > /dev/shm/cloudflare__dns-api-token.env
  mkdir -p /srv/docker/bind-mounts/pangolin/config
  docker compose -f compose.yaml config "$@"
' -- "$@"
