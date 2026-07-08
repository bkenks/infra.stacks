// authentik-outpost — parent compose (Komodo deploy entrypoint). Renders to
// compose.yaml. SCAFFOLDING: not yet deployed. Deploy target is littlebuddy; it
// dials the core Authentik server outbound and forward-auths the mesh.
//
// Secret rendered (RAM) by the infisical-agent into /dev/shm/authentik-outpost.env
// (AUTHENTIK_TOKEN — see registry agentServices.'authentik-outpost', Infisical
// infra project folder /authentik-outpost).
{
  name: 'authentik-outpost',
  include: [
    {
      path: './compose.stack.yaml',
      env_file: ['/dev/shm/authentik-outpost.env'],
    },
  ],
}
