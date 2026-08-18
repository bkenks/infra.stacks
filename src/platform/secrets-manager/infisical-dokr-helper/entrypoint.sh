#!/bin/sh
set -eu

LABEL_FILTER="${LABEL_FILTER:-com.example.watch=true}"
INTERVAL="${INTERVAL:-30}"

while true; do
  docker ps --filter "label=${LABEL_FILTER}" \
    --format '{{.ID}} {{.Names}} {{.Label "com.example.target"}}' |
    while read -r id name target; do
      printf 'match: %s (%s) target=%s\n' "$name" "$id" "$target"
    done
  sleep "$INTERVAL"
done