// Constants you compose values out of — domains, host inventory, filesystem layout.
{
  role:: {
    // The vocabulary for service keys. A stack picks its keys from here rather than
    // inventing names, so `db` is never also `database` or `postgres` in another stack, and
    // compose.libsonnet derives container/volume names from a role that means one thing.
    
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
    loopback: '127.0.0.1',
  },

  domain:: {
    homektb: 'homektb.com',
    stackform: 'stackform.app',
    couchpotatoes: 'couchpotatoes.store',
    ktbinternal: 'ktbinternal.com',
    ktbcloud: 'ktbcloud.com',
  },

  dirs:: {
    docker:: {
      root:: '/srv/docker',
      bindMounts:: '/bind-mounts',
    },

    NAS:: {
      docker:: '/volume1/docker',
      backups:: '/volume1/backups',
    },
  },

  mounts:: {
    dockerSock:: '/var/run/docker.sock:/var/run/docker.sock:ro',
  },

  labels:: {
    // Marks a container so Komodo's StopAllContainers leaves it running.
    komodoSkip:: { 'komodo.skip': '' },
  },

  condition:: {
    serviceHealthy:: 'service_healthy',
  },

  restart:: {
    unlessStopped:: 'unless-stopped',
  },
}
