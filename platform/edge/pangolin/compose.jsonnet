// pangolin — parent compose (Komodo deploy entrypoint). Renders to compose.yaml.
// This is the VPS edge tunnel/reverse-proxy stack (Pangolin + Gerbil + Traefik) —
// see compose.stack.jsonnet for why it deviates from the usual service-naming
// convention. Only deploy this to a dedicated edge host: it binds 80/443 itself
// and must NOT run alongside this repo's platform/edge/traefik on the same host.
{
  name: 'pangolin',
  include: [
    {
      path: './compose.stack.yaml',
      // Secrets rendered (RAM) by the infisical-agent on this same host — see
      // .jsonnet/lib/registry.libsonnet agentServices.pangolin.
      env_file: ['/dev/shm/pangolin.env'],
    },
  ],
}
