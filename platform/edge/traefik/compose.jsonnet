local c = import 'compose.libsonnet';

{
  name: 'traefik',
  include: [
    {
      path: './compose.stack.yaml',
      env_file: [
        c.envPath.platform('cloudflare__dns-api-token.env')
      ],
    },
  ],
}
