local c = import 'compose.libsonnet';

{
  name: 'newt',
  include: [
    {
      path: './compose.stack.yaml',
      env_file: [c.envPath.secret('newt.env')],
    },
  ],
}
