// /dev/shm/platform.env supplies the machine-identity secrets INFISICAL_CLIENT_ID/SECRET.
// AGENT_HOST/AGENT_SERVICES/INFISICAL_ADDRESS are per-host, from Komodo's stack Environment.
{
  name: 'infisical-agent',
  include: [
    {
      path: './compose.stack.yaml',
    },
  ],
}
