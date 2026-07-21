#!/usr/bin/env bash
# Onboard a fresh clone: trust mise.toml, then install the pinned toolchain.
# `mise install` fires the postinstall hook, which runs `lefthook install` to wire up
# the pre-commit build — so this is the only command a new clone needs.
set -euo pipefail

cd "$(dirname "$0")"

if ! command -v mise >/dev/null 2>&1; then
  echo "bootstrap: mise is not installed or not on PATH — install it, then re-run." >&2
  exit 1
fi

# Trust is per-machine, so a fresh clone always needs it before mise will act on the config.
mise trust
mise install
