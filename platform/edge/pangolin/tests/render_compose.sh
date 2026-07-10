#!/usr/bin/env bash
set -euo pipefail
# Runs `docker compose config` in a Linux container (for /dev/shm) after faking the runtime-only env file infisical-agent renders in prod, and the host bind-mount dir `init` would otherwise create.
# PANGOLIN_VARIANT selects the config folder (cloud|internal); Komodo sets it per instance in prod. Defaults to cloud here.
cd "$(dirname "$0")/.."
docker run --rm -e COMPOSE_PROJECT_NAME=pangolin -e "PANGOLIN_VARIANT=${PANGOLIN_VARIANT:-cloud}" -v "$PWD":/s -w /s docker:cli sh -c '
  printf "SERVER_SECRET=test\nEMAIL_SMTP_PASS=test\n" > /dev/shm/pangolin.env
  printf "CF_DNS_API_TOKEN=test\n" > /dev/shm/cloudflare__dns-api-token.env
  mkdir -p /srv/docker/bind-mounts/pangolin/config
  docker compose config "$@"
' -- "$@"
