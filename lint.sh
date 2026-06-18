#!/usr/bin/env bash

skip_dirs=()
while IFS= read -r -d '' marker; do
  skip_dirs+=("-not" "-path" "$(dirname "$marker")/*")
done < <(find . -name '.skiplint' -print0)

files=()
while IFS= read -r -d '' f; do
  files+=("$f")
done < <(find . \( -name '*.yml' -o -name '*.yaml' \) "${skip_dirs[@]}" -print0 | sort -z)

if [ ${#files[@]} -gt 0 ]; then
  dclint --fix "${files[@]}"
fi
