#!/usr/bin/env bash
# Render a .jsonnet source to YAML next to it, and print the output path.
#   Usage: .jsonnet/render.sh path/to/<name>.jsonnet
# Output naming:
#   <name>.jsonnet   -> <name>.yaml         (single YAML doc). A stack splits its
#                       source into compose.stack.jsonnet -> compose.stack.yaml
#                       (the child) and compose.jsonnet -> compose.yaml (the Komodo
#                       parent that `include`s the child + declares its env_files).
#   services.jsonnet -> templates/          (MULTI-FILE: one agent-config fragment
#                       per service; the object's string fields are written raw,
#                       one file per field name. See services.jsonnet.)
# Library imports resolve by bare name via the -J jpath below, so a source at any
# depth does `import 'lib.libsonnet'`.
set -euo pipefail

src="$1"
dir=$(dirname "$src")
lib="$(dirname "$0")/lib"

# Multi-file: services.jsonnet evaluates to { '<svc>.yaml': '<raw yaml fragment>' }.
# `-S -m` writes each string field to templates/<svc>.yaml verbatim (the per-file
# DO-NOT-EDIT header is baked into the fragment string). Render to a temp dir then
# swap so a jsonnet error never leaves a half-written templates/.
if [ "$(basename "$src")" = "services.jsonnet" ]; then
  out="$dir/templates"
  tmp=$(mktemp -d)
  jsonnet -J "$lib" -S -m "$tmp" "$src" >/dev/null
  mkdir -p "$out"
  rm -f "$out"/*.yaml
  mv "$tmp"/*.yaml "$out"/
  rmdir "$tmp"
  printf '%s\n' "$out"
  exit 0
fi

# Output extension: `.yaml` for every source EXCEPT controller.jsonnet, whose
# rendered file is mounted as controller.yml by name in traefik's compose (and was
# hand-authored as .yml historically). Special-cased on basename, like
# services.jsonnet above — keeps the mount + committed filename stable so this
# refactor is a content-only change. (Traefik's file provider loads .yml/.yaml
# alike; the mount path is what matters.)
if [ "$(basename "$src")" = "controller.jsonnet" ]; then
  ext=yml
else
  ext=yaml
fi

# Render to a temp file then swap into place — a jsonnet/python failure (caught
# by `set -e` + `pipefail` above) must never truncate the real $out to a
# half-written file (same reasoning as the services.jsonnet temp-dir swap).
out="$dir/$(basename "$src" .jsonnet).$ext"
tmp=$(mktemp "${out}.XXXXXX")
trap 'rm -f "$tmp"' EXIT

{
  printf '# GENERATED from %s by .jsonnet/render.sh — DO NOT EDIT.\n' "$(basename "$src")"
  jsonnet -J "$lib" "$src" \
    | python3 -c 'import sys, json, yaml; yaml.safe_dump(json.load(sys.stdin), sys.stdout, sort_keys=False, default_flow_style=False, width=4096)'
} >"$tmp"

mv "$tmp" "$out"
printf '%s\n' "$out"
