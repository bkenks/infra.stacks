#!/usr/bin/env bash
# Rename a docker volume by copying its contents into a new volume.
# Docker has no native volume rename, so this creates NEW, copies OLD -> NEW
# (preserving perms/owner/timestamps), then optionally removes OLD.
#
# Usage: rename-volume.sh <oldname> <newname> [-f] [-k] [-m] [--host <ssh-host>]
#   -f, --force    skip the removal prompt; also override the in-use guards
#                  (copy from a running source, or merge into a running target)
#   -k, --keep     keep the old volume (copy only, never remove)
#   -m, --merge    allow an existing target; copy OLD on top of it (files collide -> OLD wins)
#   --host HOST    run docker over ssh on HOST instead of locally
#   -h, --help     show this help
set -euo pipefail

usage() { sed -n '2,12p' "$0"; exit "${1:-0}"; }

OLD="" NEW="" FORCE=0 KEEP=0 MERGE=0 HOST=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -f|--force) FORCE=1; shift ;;
    -k|--keep)  KEEP=1;  shift ;;
    -m|--merge) MERGE=1; shift ;;
    --host)     HOST="${2:?--host needs a value}"; shift 2 ;;
    -h|--help)  usage 0 ;;
    -*)         echo "unknown flag: $1" >&2; usage 1 ;;
    *)          if [[ -z "$OLD" ]]; then OLD="$1"; elif [[ -z "$NEW" ]]; then NEW="$1"; else echo "too many args" >&2; usage 1; fi; shift ;;
  esac
done
[[ -n "$OLD" && -n "$NEW" ]] || usage 1
[[ "$OLD" != "$NEW" ]] || { echo "oldname and newname are the same" >&2; exit 1; }

d() { if [[ -n "$HOST" ]]; then ssh "$HOST" docker "$@"; else docker "$@"; fi; }

d volume inspect "$OLD" >/dev/null 2>&1 || { echo "source volume '$OLD' does not exist" >&2; exit 1; }
TARGET_EXISTS=0
if d volume inspect "$NEW" >/dev/null 2>&1; then
  if [[ "$MERGE" -ne 1 ]]; then
    echo "target volume '$NEW' already exists — refusing to overwrite (pass -m/--merge to copy into it)" >&2; exit 1
  fi
  TARGET_EXISTS=1
fi

# Only a RUNNING source is unsafe (can mutate data mid-read); stopped containers
# are safe to copy from. Override with -f.
RUN_OLD=$(d ps --filter "volume=$OLD" --format '{{.Names}}' || true)
if [[ -n "$RUN_OLD" && "$FORCE" -ne 1 ]]; then
  echo "running container(s) reference source '$OLD' — stop them first (or -f to copy live):" >&2
  echo "$RUN_OLD" | sed 's/^/  - /' >&2
  exit 1
fi

# Merging into a running target can race; warn and block unless --force.
if [[ "$TARGET_EXISTS" -eq 1 ]]; then
  TGT_INUSE=$(d ps --filter "volume=$NEW" --format '{{.Names}}' || true)
  if [[ -n "$TGT_INUSE" ]]; then
    echo "WARNING: target '$NEW' is in use by running container(s):" >&2
    echo "$TGT_INUSE" | sed 's/^/  - /' >&2
    if [[ "$FORCE" -ne 1 ]]; then
      echo "stop them first, or pass -f/--force to copy anyway." >&2
      exit 1
    fi
    echo "proceeding anyway (--force)." >&2
  fi
fi

if [[ "$TARGET_EXISTS" -eq 1 ]]; then
  echo "merging '$OLD' into existing volume '$NEW' (colliding files: OLD wins)..."
else
  echo "creating volume '$NEW' and copying from '$OLD'..."
fi
d volume create "$NEW" >/dev/null
d run --rm -v "$OLD":/from -v "$NEW":/to alpine sh -c 'cp -a /from/. /to/'
echo "copied $OLD -> $NEW"

if [[ "$KEEP" -eq 1 ]]; then
  echo "kept old volume '$OLD' (--keep). Remove it yourself when ready: docker volume rm $OLD"
  exit 0
fi

if [[ "$FORCE" -ne 1 ]]; then
  read -r -p "remove old volume '$OLD'? [y/N] " ans
  [[ "$ans" =~ ^[Yy]$ ]] || { echo "left '$OLD' in place."; exit 0; }
fi
# docker volume rm fails while ANY container (even stopped) still references OLD.
if d volume rm "$OLD" >/dev/null 2>&1; then
  echo "removed old volume '$OLD'. Done: '$NEW' is ready."
else
  STILL=$(d ps -a --filter "volume=$OLD" --format '{{.Names}}' || true)
  echo "copied to '$NEW', but '$OLD' could not be removed — still referenced by:" >&2
  echo "$STILL" | sed 's/^/  - /' >&2
  echo "recreate/redeploy those onto '$NEW' (or 'docker rm' them), then: docker volume rm $OLD" >&2
  exit 1
fi
