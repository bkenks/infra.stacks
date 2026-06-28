#!/usr/bin/env sh
# Render a .jsonnet source to YAML next to it, and print the output path.
#   Usage: .jsonnet/render.sh path/to/<name>.jsonnet
# Output naming:
#   compose.jsonnet  -> compose.stack.yaml  (the static compose.yaml parent
#                       `include`s this child and declares the interpolation
#                       env_file; the parent is hand-written and NOT regenerated)
#   services.jsonnet -> templates/          (MULTI-FILE: one agent-config fragment
#                       per service; the object's string fields are written raw,
#                       one file per field name. See services.jsonnet.)
#   <name>.jsonnet   -> <name>.yaml         (single YAML doc)
# Library imports resolve by bare name via the -J jpath below, so a source at any
# depth does `import 'lib.libsonnet'`.
set -eu

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

case "$(basename "$src")" in
  compose.jsonnet) out="$dir/compose.stack.yaml" ;;
  *) out="$dir/$(basename "$src" .jsonnet).yaml" ;;
esac

{
  printf '# GENERATED from %s by .jsonnet/render.sh — DO NOT EDIT.\n' "$(basename "$src")"
  jsonnet -J "$lib" "$src" \
    | python3 -c 'import sys, json, yaml; yaml.safe_dump(json.load(sys.stdin), sys.stdout, sort_keys=False, default_flow_style=False, width=4096)'
} >"$out"

printf '%s\n' "$out"
