#!/usr/bin/env bash
set -euo pipefail
# Validate the compose without editing it: run `docker compose config` in a
# Linux container (has /dev/shm; macOS doesn't) after faking the runtime-only
# env this template's placeholders need. compose.jsonnet ships its
# include.env_file line commented out (no secrets by default), so the
# ${...:?err} vars below are faked as plain shell vars here instead — a real
# stack with secrets wired via /dev/shm would need the printf-into-/dev/shm
# shape instead (see docuseal's tests/render_compose.sh). Delete whichever
# fake var this stack doesn't need (matches compose.stack.jsonnet).
cd "$(dirname "$0")/.."
docker run --rm -e COMPOSE_PROJECT_NAME=replaceme -v "$PWD":/s -w /s docker:cli sh -c '
  export SOME_VAR=test
  export POSTGRES_USER=test POSTGRES_PASS=test
  docker compose config "$@"
' -- "$@"
