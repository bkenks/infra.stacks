// newt — parent compose (Komodo deploy entrypoint). Renders to compose.yaml.
// This is the Pangolin site connector for the traefik-controller role — see
// compose.stack.jsonnet. Deploy it to any host carrying that role; it needs the
// host's Traefik reachable on shared-proxy.
local lib = import 'lib.libsonnet';
local reg = lib.registry;

{
  name: 'newt',
  include: [
    {
      path: './compose.stack.yaml',
      // NEWT_ID/NEWT_SECRET rendered (RAM) by the infisical-agent on this host
      // from the role-scoped Infisical folder /roles/traefik-controller
      // (registry agentServices.newt).
      env_file: [reg.envFiles.secretsPath('newt.env')],
    },
  ],
}
