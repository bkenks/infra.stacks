#!/usr/bin/env bash
set -euo pipefail
# Validate the compose without editing it: run `docker compose config` in a
# Linux container (has /dev/shm; macOS doesn't) after faking the runtime-only
# env file the infisical-agent renders in prod, and the host bind-mount dir
# `init` would otherwise create.
cd "$(dirname "$0")/.."
docker run --rm -e COMPOSE_PROJECT_NAME=pangolin -v "$PWD":/s -w /s docker:cli sh -c '
  printf "SERVER_SECRET=test\nEMAIL_SMTP_PASS=test\n" > /dev/shm/pangolin.env
  mkdir -p /srv/docker/bind-mounts/pangolin/config
  docker compose config "$@"
' -- "$@"
