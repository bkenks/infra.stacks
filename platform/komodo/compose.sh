#!/usr/bin/env bash
set -euo pipefail

# compose.sh
# desc: runner for docker compose commands to ensure the correct flags are always ran along with your compose commands like "up" or "logs -f"
# Interpolation vars come from interpolation-envs/general.env via compose.yaml's include.env_file.

docker compose "$@"
