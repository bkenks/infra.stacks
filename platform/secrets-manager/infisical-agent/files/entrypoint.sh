#!/bin/sh
# Infisical Agent entrypoint.
#
# We don't ship a static per-host agent config. The host passes AGENT_SERVICES (a
# space/comma list of service names) and we ASSEMBLE the agent config at startup
# by concatenating pre-rendered fragments. Each service has a self-contained
# config fragment at /agent/templates/<svc>.yaml — one `templates:` list entry
# with an INLINE template-content — generated from registry.libsonnet by
# services.jsonnet (the dump/map/raw template bodies are built there, NOT here).
# So this script does no YAML parsing and no template generation; it just picks
# the named fragments, substitutes the one runtime-only value (${AGENT_HOST}),
# and appends them under a `templates:` header.
#
# One long-running service (no compose profiles). How it reaches Infisical is just
# the INFISICAL_ADDRESS env var — public URL by default; the Infisical host
# overrides it to the internal http://infisical-app:8080 (reachable over the proxy
# network the agent always joins, before Traefik/the public URL exist).
#
# Creds: written from env (INFISICAL_CLIENT_ID/SECRET, the Komodo/node path) when
# present, otherwise the pre-written /dev/shm files are used (the Ansible/
# control-plane path). remove_client_secret_on_read wipes the secret after read.
set -eu

: "${AGENT_HOST:?AGENT_HOST is required (host name; drives \${AGENT_HOST} secret-path subs)}"
: "${AGENT_SERVICES:?AGENT_SERVICES is required (space/comma list of services from templates/)}"
: "${INFISICAL_ADDRESS:?INFISICAL_ADDRESS is required (public URL by default; per-host override)}"

templates="/agent/templates"         # pre-rendered per-service config fragments
config="/tmp/agent.generated.yaml"
cred_id="/dev/shm/agent.client-id"
cred_secret="/dev/shm/agent.client-secret"

# --- creds -----------------------------------------------------------------
# Write from env only when provided (node path); skip when absent so a
# pre-written file (control-plane/Ansible path) is left untouched.
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

# --- assemble config from AGENT_SERVICES + pre-rendered fragments -----------
cat > "$config" <<EOF
infisical:
  address: "${INFISICAL_ADDRESS}"
  exit-after-auth: false
  revoke-credentials-on-shutdown: false

auth:
  type: "universal-auth"
  config:
    client-id: "${cred_id}"
    client-secret: "${cred_secret}"
    remove_client_secret_on_read: true

templates:
EOF

# Normalise commas to spaces so AGENT_SERVICES accepts either separator.
services=$(printf '%s' "$AGENT_SERVICES" | tr ',' ' ')

for svc in $services; do
  frag="$templates/${svc}.yaml"
  [ -f "$frag" ] || { echo "infisical-agent: unknown service '$svc' (no $frag)" >&2; exit 1; }
  # The Infisical template engine has no env access, so ${AGENT_HOST} baked into a
  # fragment's secret path is substituted here (no-op for fragments without it).
  sed "s|\${AGENT_HOST}|${AGENT_HOST}|g" "$frag" >> "$config"
done

# --- healthcheck plumbing --------------------------------------------------
# Mirror the agent's output to a log file the healthcheck can read. The agent
# only logs to stdout and a Docker healthcheck can't read `docker logs`, so we
# write its output to /tmp/agent.log (container-local, truncated on every start).
# `tail -f` streams the same log to stdout so `docker logs` / Komodo still show
# everything, and `exec`-ing the agent keeps it as PID 1 for a clean SIGTERM.
#
# Health is a CURRENT-STATE question, not a historical one: a failing template or
# auth keeps the process alive (liveness never flips), but an append-only error
# log can't be grepped for "currently fine" because the agent is SILENT on
# success — old ERR lines would linger and pin it unhealthy forever. So instead we
# stamp /tmp/agent.last_err with the epoch of every ERR/FTL/PNC line; the
# healthcheck flags unhealthy only while an error was seen recently (see
# compose/agent.yml). A still-broken agent re-logs within the window (auth
# retries ~30s, template polls 1m) and stays unhealthy; once the errors stop the
# last stamp ages out and the container returns to healthy with no restart.
log="/tmp/agent.log"
err_stamp="/tmp/agent.last_err"
: > "$log"
rm -f "$err_stamp"
tail -f "$log" &

# Watch the agent's output and stamp the time of each error line. The ANSI-wrapped
# zerolog level (e.g. ESC[31mERR ESC[0m) still matches the *ERR* glob; uppercase
# ERR/FTL/PNC appear only in the level column, never in mixed-case message text
# like "APIError", so this won't false-positive.
tail -f "$log" | while IFS= read -r line; do
  case "$line" in
    *ERR*|*FTL*|*PNC*) date +%s > "$err_stamp" ;;
  esac
done &

echo "infisical-agent: $AGENT_HOST | address $INFISICAL_ADDRESS | services: $services"
exec infisical agent --config "$config" >> "$log" 2>&1
