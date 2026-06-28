#!/bin/sh
# Infisical Agent entrypoint.
#
# We don't ship a static per-host agent config anymore. Instead the host passes
# AGENT_SERVICES (a space/comma list of service names) and we GENERATE the agent
# config at startup from the service catalogue (services.yaml, itself generated
# from registry.libsonnet's agentServices):
#   - type=dump  listSecrets folder dump (whole Infisical folder -> KEY=VALUE)
#   - type=map   explicit OUTPUT=FROM renames/duplications (catalogue `keys`)
#   - type=raw   a single secret's raw value, no KEY= prefix (catalogue `key`)
# Every template is generated here from the catalogue — there are NO hand-written
# .tpl files and no template mount.
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
: "${AGENT_SERVICES:?AGENT_SERVICES is required (space/comma list of services from services.yaml)}"
: "${INFISICAL_ADDRESS:?INFISICAL_ADDRESS is required (public URL by default; per-host override)}"

registry="/agent/services.yaml"
tpl_out="/agent-templates"           # generated agent templates (all built from the catalogue)
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

# Extract one field of a service from the generated YAML catalogue. The schema is
# fixed (pyyaml output, 2-space indent), so a small awk state machine is enough —
# no yq needed. Empty output means the service or field is absent.
#   services:
#     <svc>:           <- 2-space header
#       dest: ...      <- 4-space fields
#       env: ...
#       folder: ...
#       project: ...
#       type: ...
field() {
  awk -v svc="$1" -v key="$2" '
    /^  [^[:space:]].*:[[:space:]]*$/ {                 # "  <svc>:" header (2-space)
      s=$0; sub(/^  /,"",s); sub(/:[[:space:]]*$/,"",s); cur=(s==svc); next
    }
    /^[^[:space:]]/ { cur=0 }                            # back to column 0 (e.g. "services:")
    cur && /^    [^[:space:]]/ {                         # "    key: value" (4-space)
      l=$0; sub(/^    /,"",l); k=l; sub(/:.*/,"",k)
      if (k==key) { v=l; sub(/^[^:]*:[[:space:]]*/,"",v); gsub(/^"|"$/,"",v); print v; exit }
    }
  ' "$registry"
}

# Normalise commas to spaces so AGENT_SERVICES accepts either separator.
services=$(printf '%s' "$AGENT_SERVICES" | tr ',' ' ')

for svc in $services; do
  project=$(field "$svc" project)
  [ -n "$project" ] || { echo "infisical-agent: unknown service '$svc' (not in services.yaml)" >&2; exit 1; }
  env=$(field "$svc" env)
  folder=$(field "$svc" folder)
  dest=$(field "$svc" dest)
  type=$(field "$svc" type)

  # The Infisical template engine has no env access, so ${AGENT_HOST} in a path
  # is substituted here (only var substituted; secret VALUES are fetched at render).
  folder=$(printf '%s' "$folder" | sed "s|\${AGENT_HOST}|${AGENT_HOST}|g")

  tpl="$tpl_out/${svc}.tpl"
  case "$type" in
    dump)
      # Whole Infisical folder -> KEY=VALUE (secret names already match env names).
      {
        printf '{{- with listSecrets "%s" "%s" "%s" }}\n' "$project" "$env" "$folder"
        printf '{{- range . }}\n'
        printf '{{ .Key }}={{ .Value }}\n'
        printf '{{- end }}\n'
        printf '{{- end }}\n'
      } > "$tpl"
      ;;
    map)
      # Explicit OUTPUT=FROM renames/duplications (space-separated pairs from `keys`).
      : > "$tpl"
      for pair in $(field "$svc" keys); do
        out=${pair%%=*}
        from=${pair#*=}
        printf '%s={{ with getSecretByName "%s" "%s" "%s" "%s" }}{{ .Value }}{{ end }}\n' \
          "$out" "$project" "$env" "$folder" "$from" >> "$tpl"
      done
      ;;
    raw)
      # A single secret's RAW value, no KEY= prefix (for *.key files etc.).
      printf '{{- with getSecretByName "%s" "%s" "%s" "%s" -}}{{ .Value }}{{- end -}}\n' \
        "$project" "$env" "$folder" "$(field "$svc" key)" > "$tpl"
      ;;
    *)
      echo "infisical-agent: service '$svc' has unknown type '$type'" >&2
      exit 1
      ;;
  esac

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
