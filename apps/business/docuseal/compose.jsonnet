local c = import 'compose.libsonnet';

{
  name: 'docuseal',
  include: [
    {
      path: './compose.stack.yaml',
      env_file: ['/dev/shm/docuseal.env', '/dev/shm/postgres.env'],
    },
  ],
}
