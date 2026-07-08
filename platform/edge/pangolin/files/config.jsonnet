// config.jsonnet — SOURCE for config.yaml (the Pangolin app config).
//
// Renders (via .jsonnet/render.py) to config.yaml, mounted read-only into the
// pangolin container at /app/config/config.yml (see compose.stack.jsonnet). DO
// NOT edit config.yaml — edit this source and re-render.
//
// ⚠️ safe_dump strips YAML comments, so config.yaml carries only the render.py
// DO-NOT-EDIT header — all operational knowledge lives HERE.
//
// The dashboard host and CORS origin derive from reg.domains.ktbinternal, so a
// domain migration follows automatically. Docs: https://docs.pangolin.net/
local reg = import 'registry.libsonnet';

local baseDomain = reg.domains.ktbinternal;  // ktbinternal.com
local host = 'pangolin.' + baseDomain;       // pangolin.ktbinternal.com

{
  gerbil: {
    start_port: 51820,
    base_endpoint: host,
  },

  app: {
    dashboard_url: 'https://' + host,
    log_level: 'info',
    telemetry: {
      anonymous_usage: true,
    },
  },

  domains: {
    domain1: {
      base_domain: baseDomain,
    },
  },

  server: {
    // server.secret is supplied via the SERVER_SECRET env var (infisical-agent).
    // It must be OMITTED here, not blanked — Pangolin's config loader only
    // applies the env override when the key is ABSENT; `secret: ''` counts as
    // "defined" and fails validation (>=8 chars) before the env var is ever
    // consulted. So: do not add a `secret` field to this object.
    cors: {
      origins: ['https://' + host],
      methods: ['GET', 'POST', 'PUT', 'DELETE', 'PATCH'],
      allowed_headers: ['X-CSRF-Token', 'Content-Type'],
      credentials: false,
    },
    maxmind_db_path: './config/GeoLite2-Country.mmdb',
    maxmind_asn_path: './config/GeoLite2-ASN.mmdb',
  },

  email: {
    smtp_host: 'smtp.resend.com',
    smtp_port: 465,
    smtp_user: 'resend',
    // smtp_pass is supplied via the EMAIL_SMTP_PASS env var (infisical-agent) —
    // OMITTED here for the same reason as server.secret above.
    no_reply: 'pangolin@notify.' + baseDomain,
  },

  flags: {
    require_email_verification: true,
    disable_signup_without_invite: true,
    disable_user_create_org: false,
    allow_raw_resources: true,
  },
}
