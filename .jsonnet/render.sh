#!/usr/bin/env sh
# Render a .jsonnet source to YAML next to it, and print the output path.
#   Usage: .jsonnet/render.sh path/to/<name>.jsonnet
# Output naming:
#   compose.jsonnet -> compose.stack.yaml   (the static compose.yaml parent
#                      `include`s this child and declares the interpolation
#                      env_file; the parent is hand-written and NOT regenerated)
#   <name>.jsonnet  -> <name>.yaml          (e.g. services.jsonnet -> services.yaml)
# Library imports resolve by bare name via the -J jpath below, so a source at any
# depth does `import 'infra.libsonnet'`.
set -eu

src="$1"
dir=$(dirname "$src")
lib="$(dirname "$0")/lib"

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
