// replaceme — parent compose (Komodo deploy entrypoint). Renders to
// compose.yaml. Copy this whole .template/ directory to scaffold a new stack,
// then rename `stack` here (and in compose.stack.jsonnet) to match.
//
// Worked examples elsewhere in this repo:
//   apps/business/docuseal              — simple, single-service, w/ shared-postgres
//   apps/personal/paperless (or apps/business/openproject) — multi-service
local stack = 'replaceme';

{
  name: stack,
  include: [
    {
      path: './compose.stack.yaml',
      // Secrets rendered (RAM) by the infisical-agent on this same host. Only
      // include this line if the stack has secrets — see
      // .jsonnet/lib/registry.libsonnet agentServices for the catalogue
      // format, and add an entry there.
      // env_file: ['/dev/shm/' + stack + '.env'],
    },
  ],
}
