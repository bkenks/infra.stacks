// Raw constants — the values that have no structure, only a spelling.
//
// Anything computed from these (an endpoint, a shared network, a secret path) lives in
// registry.libsonnet instead. Nothing here refers to anything else.
{
  // The vocabulary for service keys. A stack picks its keys from here rather than
  // inventing names, so `db` is never also `database` or `postgres` in another stack.
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

  ip:: {
    // Published ports bind here: apps are reached over the tailnet or the edge proxy, so a
    // port that is not loopback-bound is a mistake rather than a default.
    loopback:: '127.0.0.1',
  },

  domain:: {
    homektb:: 'homektb.com',
    stackform:: 'stackform.app',
    couchpotatoes:: 'couchpotatoes.store',
    ktbinternal:: 'ktbinternal.com',
    ktbcloud:: 'ktbcloud.com',
  },

  dirs:: {
    docker:: {
      root:: '/srv/docker',
      bindMounts:: '/srv/docker/bind-mounts',
    },

    // Rootless docker's data root on the hosts that run it.
    rootlessSrv:: '/rootless-srv',

    nas:: {
      docker:: '/volume1/docker',
      backups:: '/volume1/backups',
    },

    // tmpfs. infisical-agent renders every secret here, so it never touches a disk.
    secrets:: '/dev/shm',
  },

  // There is no cluster DNS. A container reaches its own host through the docker gateway,
  // which is how every cross-stack call is made: publish a port, then dial it here.
  // `hostGateway.extraHosts` is what makes the name resolve inside the container.
  hostGateway:: {
    host:: 'host.docker.internal',
    extraHosts:: ['host.docker.internal:host-gateway'],
  },

  mounts:: {
    dockerSock:: '/var/run/docker.sock:/var/run/docker.sock:ro',
    // Restarting a container is a write on the socket, so this one is deliberately not :ro.
    dockerSockRW:: '/var/run/docker.sock:/var/run/docker.sock',
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
