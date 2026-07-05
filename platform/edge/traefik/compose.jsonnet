// traefik — parent compose (Komodo deploy entrypoint). Renders to compose.yaml.
// Interpolation env_file supplies CF_DNS_API_TOKEN for the DNS-01 ACME
// challenge — rendered by the infisical-agent (registry.libsonnet
// agentServices.'cloudflare__dns-api-token'); ansible seeds it directly on
// tier-0 bootstrap hosts before the agent is up (envFiles.platform's
// ANSIBLE_SECRETS_FILE fallback).
local lib = import 'lib.libsonnet';
local reg = lib.registry;

{
  name: 'traefik',
  include: [
    {
      path: './compose.stack.yaml',
      env_file: [
        reg.envFiles.platform('cloudflare__dns-api-token.env')
      ],
    },
  ],
}
