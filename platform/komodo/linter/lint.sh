#!/usr/bin/env bash

# Resolve paths relative to this script so it works regardless of cwd.
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"

files=()
while IFS= read -r -d '' f; do
  files+=("$f")
done < <(find "${repo_root}" \
  \( -path '*/.git' -o -path '*/.github' \) -prune -o \
  \( -name '*.yml' -o -name '*.yaml' \) -print0 | sort -z)

if [ ${#files[@]} -gt 0 ]; then
  dclint --config "${script_dir}/.dclintrc" --fix "${files[@]}"
fi
