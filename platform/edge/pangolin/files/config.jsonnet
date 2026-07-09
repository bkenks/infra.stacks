// Renders to config.yaml, mounted read-only into pangolin at /app/config/config.yml.
// Edit this source, not the yaml — safe_dump strips comments, so the yaml carries only
// a DO-NOT-EDIT header and all operational knowledge lives HERE.
local reg = import 'registry.libsonnet';

local baseDomain = reg.domains.ktbinternal;
local host = 'pangolin.' + baseDomain;

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
    // Public plane (Authentik + *.ktbcloud.com Resources); wildcard cert is
    // requested once by authentik-router in dynamic_config.jsonnet.
    domain2: {
      base_domain: reg.domains.ktbcloud,
    },
  },

  server: {
    // server.secret comes from SERVER_SECRET env (infisical-agent) — must be OMITTED
    // here, not blanked. Pangolin only applies the env override when the key is ABSENT;
    // `secret: ''` counts as "defined" and fails validation before the env var is read.
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
    // smtp_pass: EMAIL_SMTP_PASS env (infisical-agent) — omitted for the same reason as server.secret.
    no_reply: 'pangolin@notify.' + baseDomain,
  },

  flags: {
    require_email_verification: true,
    disable_signup_without_invite: true,
    disable_user_create_org: false,
    allow_raw_resources: true,
  },
}
