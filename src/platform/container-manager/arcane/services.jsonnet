local lib = import 'lib.libsonnet';
local refs = import 'refs.libsonnet';

// FIXME: carried over from the stack template — this is not arcane's image.
local appVersion = 'latest';
local appPort = '3552';

{
  name: refs.name,
  networks: refs.networks,
  volumes: refs.appData.declare,

  services: {
    [refs.app.key]: {
      container_name: refs.app.container,
      image: 'ghcr.io/example/example:' + appVersion,
      restart: lib.restart.unlessStopped,
      volumes: [
        refs.appData.mount('/app/data'),
        lib.mounts.dockerSock,
      ],
      environment: {
        ENCRYPTION_KEY: '',
        JWT_SECRET: '',
        TZ: 'EST',
      },
      cgroup: 'host',
      expose: [appPort],
      ports: ['18000:' + appPort],
    },
  },
}
