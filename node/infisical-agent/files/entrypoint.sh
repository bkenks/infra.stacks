#!/bin/sh
# Infisical Agent entrypoint. Serves both deploy modes:
#   - Komodo (standard): creds arrive as env (INFISICAL_CLIENT_ID/SECRET) and are
#     written to /dev/shm here.
#   - Ansible (init): Ansible has already written /dev/shm/agent.init.client-id|secret
#     (the .init prefix avoids colliding with the standard agent's file), so the
#     env vars are absent and we just use the existing files.
# Either way the agent reads the files; remove_client_secret_on_read in the agent
# config wipes the secret file right after it's read.
set -eu

: "${AGENT_HOST:?AGENT_HOST is required (selects files/configs/<host>...yaml)}"

# Cred file paths are keyed to the profile via AGENT_CONFIG_SUFFIX (".init" for
# the init profile, empty for standard) so the init (Ansible-written) and standard
# (Komodo env-written) agents never share a file in /dev/shm. They run with
# different effective uids — Ansible as host root, the Komodo container often
# userns-remapped — and on the sticky /dev/shm (1777) a non-owner can't overwrite
# the other's file. The matching <host>.init.yaml / <host>.yaml configs point at
# these same paths.
cred_id="/dev/shm/agent${AGENT_CONFIG_SUFFIX:-}.client-id"
cred_secret="/dev/shm/agent${AGENT_CONFIG_SUFFIX:-}.client-secret"

# Write creds from env only when provided (Komodo path). Skip when absent so the
# Ansible-written files are left untouched.
if [ -n "${INFISICAL_CLIENT_ID:-}" ]; then
  printf '%s' "$INFISICAL_CLIENT_ID" > "$cred_id"
fi
if [ -n "${INFISICAL_CLIENT_SECRET:-}" ]; then
  printf '%s' "$INFISICAL_CLIENT_SECRET" > "$cred_secret"
fi

if [ ! -s "$cred_id" ] || [ ! -s "$cred_secret" ]; then
  echo "infisical-agent: missing $cred_id or $cred_secret" >&2
  echo "  provide INFISICAL_CLIENT_ID / INFISICAL_CLIENT_SECRET (env) or pre-write the files" >&2
  exit 1
fi
chmod 0600 "$cred_id" "$cred_secret" 2>/dev/null || true

config="/agent-configs/${AGENT_HOST}${AGENT_CONFIG_SUFFIX:-}.yaml"
if [ ! -f "$config" ]; then
  echo "infisical-agent: config not found: $config" >&2
  exit 1
fi

# Render shared templates: one .tpl per stack lives in /agent-configs/templates
# and is referenced by every host's config via `source-path`. The Infisical
# agent's Go-template engine has NO access to the environment, so host-specific
# secret paths (e.g. cloudflared's /hosts/<host>/cloudflared) can't be expressed
# inside a template. We bridge that here by substituting ${AGENT_HOST} into a
# writable copy that the configs point at (/agent-templates/<stack>.tpl). Files
# without the placeholder are copied through unchanged. This is the ONLY var
# substituted — secret values are still fetched by the agent at render time.
tpl_src="/agent-configs/templates"
tpl_out="/agent-templates"
if [ -d "$tpl_src" ]; then
  mkdir -p "$tpl_out"
  for f in "$tpl_src"/*.tpl; do
    [ -e "$f" ] || continue
    sed "s|\${AGENT_HOST}|${AGENT_HOST}|g" "$f" > "$tpl_out/$(basename "$f")"
  done
fi

# Mirror the agent's output to a log file the healthcheck can scan. The agent
# only logs to stdout, and a Docker healthcheck can't read `docker logs`, so we
# tee its output to /tmp/agent.log (container-local, truncated on every start)
# and the healthcheck greps it for ` ERR ` lines. A permanently failing template
# (e.g. wrong secret path -> repeated ERR + 30s retry) keeps the process alive,
# so liveness alone never flags it — the log scan does. `tail -f` streams the
# same log to stdout so `docker logs` / Komodo still show everything, and
# `exec`-ing the agent keeps it as PID 1 for a clean SIGTERM on redeploy.
log="/tmp/agent.log"
: > "$log"
tail -f "$log" &

echo "infisical-agent: starting with $config"
exec infisical agent --config "$config" >> "$log" 2>&1
