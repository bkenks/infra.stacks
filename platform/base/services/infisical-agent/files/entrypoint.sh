#!/bin/sh
# Infisical Agent entrypoint.
#
# We don't ship a static per-host agent config anymore. Instead the host passes
# AGENT_SERVICES (a space/comma list of service names) and we GENERATE the agent
# config at startup from the service registry (files/services.tab):
#   - type=dump   services become a listSecrets folder dump (whole Infisical
#                 folder -> KEY=VALUE), generated on the fly.
#   - type=custom services use their hand-written template
#                 (files/configs/templates/<service>.tpl) verbatim — for renamed
#                 or duplicated keys, host-scoped paths, or raw-value files.
#
# Two deploy modes, selected by compose profile (see compose/agent.yml); the only
# per-mode difference is INFISICAL_ADDRESS (+ the control-plane joining the proxy
# network so it can reach infisical-app directly before Traefik/the public URL
# exist). Both modes are long-running and render the same way.
#
# Creds: written from env (INFISICAL_CLIENT_ID/SECRET, the Komodo/node path) when
# present, otherwise the pre-written /dev/shm files are used (the Ansible/
# control-plane path). remove_client_secret_on_read wipes the secret after read.
set -eu

: "${AGENT_HOST:?AGENT_HOST is required (host name; drives \${AGENT_HOST} secret-path subs)}"
: "${AGENT_SERVICES:?AGENT_SERVICES is required (space/comma list of services from services.tab)}"
: "${INFISICAL_ADDRESS:?INFISICAL_ADDRESS is required (set per mode in compose/agent.yml)}"

registry="/agent/services.tab"
tpl_src="/agent-configs/templates"   # hand-written custom templates (read-only mount)
tpl_out="/agent-templates"           # writable copies / generated dump templates
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

# --- generate config from AGENT_SERVICES + registry ------------------------
mkdir -p "$tpl_out"
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

# Look a service up in the registry: skip comments/blanks, trim the first
# pipe-delimited column, print the whole matching row. Non-zero if not found.
lookup() {
  awk -F'|' -v svc="$1" '
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*$/ { next }
    { c=$1; gsub(/^[[:space:]]+|[[:space:]]+$/, "", c); if (c == svc) { print; found=1; exit } }
    END { exit !found }
  ' "$registry"
}

# Pull and trim a given column (1-based) from a registry row.
col() { printf '%s' "$1" | awk -F'|' -v n="$2" '{c=$n; gsub(/^[ \t]+|[ \t]+$/,"",c); print c}'; }

# Normalise commas to spaces so AGENT_SERVICES accepts either separator.
services=$(printf '%s' "$AGENT_SERVICES" | tr ',' ' ')

for svc in $services; do
  row=$(lookup "$svc") || { echo "infisical-agent: unknown service '$svc' (not in services.tab)" >&2; exit 1; }

  project=$(col "$row" 2)
  env=$(col "$row" 3)
  folder=$(col "$row" 4)
  dest=$(col "$row" 5)
  type=$(col "$row" 6)

  # The Infisical template engine has no env access, so ${AGENT_HOST} in a path
  # is substituted here (only var substituted; secret VALUES are fetched at render).
  folder=$(printf '%s' "$folder" | sed "s|\${AGENT_HOST}|${AGENT_HOST}|g")

  if [ "$type" = "custom" ]; then
    if [ ! -f "$tpl_src/${svc}.tpl" ]; then
      echo "infisical-agent: custom service '$svc' has no template $tpl_src/${svc}.tpl" >&2
      exit 1
    fi
    sed "s|\${AGENT_HOST}|${AGENT_HOST}|g" "$tpl_src/${svc}.tpl" > "$tpl_out/${svc}.tpl"
  else
    # Folder dump: render the entire Infisical folder as KEY=VALUE.
    {
      printf '{{- with listSecrets "%s" "%s" "%s" }}\n' "$project" "$env" "$folder"
      printf '{{- range . }}\n'
      printf '{{ .Key }}={{ .Value }}\n'
      printf '{{- end }}\n'
      printf '{{- end }}\n'
    } > "$tpl_out/${svc}.tpl"
  fi

  {
    printf '  - source-path: %s/%s.tpl\n' "$tpl_out" "$svc"
    printf '    destination-path: /dev/shm/%s\n' "$dest"
    printf '    config:\n'
    printf '      polling-interval: "1m"\n'
  } >> "$config"
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
