// env_file komodo_core.env supplies KOMODO_*/MONGO_* secrets; named to avoid colliding with
// the committed ./core.env (non-secret tunables). DOCKER_VOLUMES comes from Komodo's stack Environment.
local c = import 'compose.libsonnet';
local reg = import 'registry.libsonnet';
local secrets = reg.infisical.services;

local stack = 'komodo';
local s = c.stack(stack);
local n = s.names;
local app = reg.roles.app;
local db = reg.roles.db;

local version = '2.1.2';
local mongoVersion = '8.2.4';
local komodoEnv = './core.env';
local stackDir = '/bind-mounts/dcm';

local manifest = {
  name: stack,

  services: {
    [app]: {
      image: 'ghcr.io/moghtech/komodo-core:' + version,
      container_name: n.container(app),
      depends_on: [ db ],
      volumes: [
        app + ':/config/keys',
        reg.server.dir.docker.root + stackDir + '/komodo/data/backups:/backups',
        reg.server.dir.docker.root + stackDir + '/komodo/data/syncs:/syncs',
      ],
      env_file: komodoEnv,
      environment: {
        KOMODO_HOST: 'https://komo.' + reg.domains.ktbinternal,
        // Secrets — interpolated from /dev/shm/platform.env (parent include.env_file)
        KOMODO_DATABASE_USERNAME: '${KOMO_DB_USERNAME:?err}',
        KOMODO_DATABASE_PASSWORD: '${KOMO_DB_PASSWORD:?err}',
        KOMODO_WEBHOOK_SECRET: '${KOMO_WEBHOOK_SECRET:?err}',
        KOMODO_JWT_SECRET: '${KOMO_JWT_SECRET:?err}',
      },
      // Published directly — the UI is reached via this exposed port.
      ports: ['9120:9120'],
      extra_hosts: ['host.docker.internal:host-gateway'],
      restart: 'unless-stopped',
      init: true,
      networks: {
        default: {
          aliases: [n.container('core')]
        },
      },
      labels: s.komodoSkip,
    },

    [db]: {
      image: 'mongo:' + mongoVersion,
      container_name: n.container(db),  // referenced as komodo_db in core.env
      volumes: [
        reg.server.dir.docker.root + stackDir + '/mongo/data:/data/db',
        reg.server.dir.docker.root + stackDir + '/mongo/config:/data/configdb',
      ],
      env_file: komodoEnv,
      environment: {
        // Secrets — interpolated from /dev/shm/platform.env (parent include.env_file)
        MONGO_INITDB_ROOT_USERNAME: '${KOMO_DB_USERNAME:?err}',
        MONGO_INITDB_ROOT_PASSWORD: '${KOMO_DB_PASSWORD:?err}',
      },
      ports: ['27017:27017'],
      command: '--quiet --wiredTigerCacheSizeGB 0.25',
      restart: 'unless-stopped',
      networks: {
        default: {
          aliases: [n.container(db)]
        },
      },
      labels: s.komodoSkip,
    },
  },

  volumes: {
    // Distinct from komodo-periphery's keys volume so PKI never cross-contaminates.
    [app]: {
      name: n.volume(app)
    },
    [db]: {
      name: n.volume(db),
    },
  },

  networks:
    s.network.default,
};

c.render(stack, manifest, [secrets.komodo.platformPath])
