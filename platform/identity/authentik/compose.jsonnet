// authentik — parent compose (Komodo deploy entrypoint). Renders to compose.yaml.
// SCAFFOLDING: not yet deployed anywhere — a host opts in via Komodo. Deploy
// target is the core identity host (littlebuddy); it owns shared-edge.
//
// Secrets rendered (RAM) by the infisical-agent on this host into
// /dev/shm/authentik.env (SECRET_KEY / PG password / bootstrap creds — see
// registry agentServices.authentik, Infisical infra project folder /authentik).
{
  name: 'authentik',
  include: [
    {
      path: './compose.stack.yaml',
      env_file: ['/dev/shm/authentik.env'],
    },
  ],
}
