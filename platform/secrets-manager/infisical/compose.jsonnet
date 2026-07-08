local c = import 'compose.libsonnet';

{
  name: 'infisical',
  include: [
    {
      path: './compose.stack.yaml',
      env_file: [c.envPath.platform('infisical.env')],
    },
  ],
}
