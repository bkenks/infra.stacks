{
  role:: {
    // User-facing / entry
    APP:: 'app',
    PROXY:: 'proxy',
    WEB:: 'web',
    API:: 'api',
    ASSETS:: 'assets',

    // Network
    DNS:: 'dns',

    // Compute
    SERVER:: 'server',
    AGENT:: 'agent',
    TUNNEL:: 'tunnel',
    WORKER:: 'worker',
    SCHEDULER:: 'scheduler',
    CONSUMER:: 'consumer',
    RUNNER:: 'runner',

    // State
    DB:: 'db',
    CACHE:: 'cache',
    QUEUE:: 'queue',
    SEARCH:: 'search',
    STORAGE:: 'storage',
    VECTOR:: 'vector',

    // Lifecycle
    MIGRATE:: 'migrate',
    SEEDER:: 'seeder',
    BACKUP:: 'backup',

    // Ops
    METRICS:: 'metrics',
    LOGS:: 'logs',
    MAIL:: 'mail',
  },

  ip:: { loopback:: '127.0.0.1' },

  domain:: {
    ktbdev::          'ktb.dev',
    ktbinternal::     'ktbinternal.com',
    ktbcloud::        'ktbcloud.com',
  },

  dirs:: {
    docker:: {
      root::
        '/srv/docker',
      bindMounts::
        '/srv/docker/bind-mounts',
    },

    rootlessSrv::
      '/rootless-srv',

    nas:: {
      docker::
        '/volume1/docker',
      backups::
        '/volume1/backups',
    },

    // tmpfs. infisical-agent renders every secret here, so it never touches a disk.
    secrets::
      '/dev/shm',
  },

  mounts:: {
    dockerSock::
      '/var/run/docker.sock:/var/run/docker.sock:ro',
    dockerSockRW::
      '/var/run/docker.sock:/var/run/docker.sock',
  },

  labels:: {
    // Marks a container so Komodo's StopAllContainers leaves it running.
    komodoSkip:: { 'komodo.skip': '' },
  },

  condition:: {
    started:: 'service_started',
    healthy:: 'service_healthy',
    completed:: 'service_completed_successfully',
  },

  restart:: {
    always:: 'always',
    unlessStopped:: 'unless-stopped',
    onFailure(times):: 'on-failure:' + times,
  },
}
