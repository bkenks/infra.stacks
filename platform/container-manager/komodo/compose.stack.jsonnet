// komodo — Komodo Core (UI/control plane) + Mongo (config store).
//
// Source of truth: this file compiles to compose.yaml (do not edit the YAML).
// Names, aliases, versions, and the public domain come from this file or the
// shared registry. Only per-HOST runtime values stay as ${...} so docker
// compose interpolates them at deploy time.
local c = import 'compose.libsonnet';
local reg = import 'registry.libsonnet';

//

local stack = 'komodo';
local s = c.stack(stack);
local n = s.names;
local app = reg.roles.app;
local db = reg.roles.db;

// 

local version = '2.1.2';        // Komodo image tag (was interpolation var KOMO_VERS)
local mongoVersion = '8.2.4';
local komodoEnv = './core.env';
local stackDir = '/bind-mounts/dcm';

{
  name: stack,

  services: {
    [app]: {
      image: 'ghcr.io/moghtech/komodo-core:' + version,
      container_name: n.container(app),
      depends_on: [ db ],
      volumes: [
        app + ':/config/keys',  // auto-generated v2 PKI keys
        reg.server.dir.docker.root + stackDir + '/komodo/data/backups:/backups',
        reg.server.dir.docker.root + stackDir + '/komodo/data/syncs:/syncs',
      ],
      env_file: komodoEnv,  // committed non-secret config (KOMODO_* tunables)
      environment: {
        // Public URL behind Traefik; built from the registry's root domain.
        KOMODO_HOST: 'https://komo.' + reg.domains.ktbinternal,
        // Secrets — interpolated from /dev/shm/platform.env (parent include.env_file)
        KOMODO_DATABASE_USERNAME: '${KOMO_DB_USERNAME:?err}',
        KOMODO_DATABASE_PASSWORD: '${KOMO_DB_PASSWORD:?err}',
        KOMODO_WEBHOOK_SECRET: '${KOMO_WEBHOOK_SECRET:?err}',
        KOMODO_JWT_SECRET: '${KOMO_JWT_SECRET:?err}',
      },
      // 9120 published as a recovery fallback — Komodo manages Traefik, so don't
      // lock yourself out of the UI.
      ports: ['9120:9120'],
      extra_hosts: ['host.docker.internal:host-gateway'],
      restart: 'unless-stopped',
      init: true,
      networks: {
        default: {
          aliases: [n.container('core')]
        },
        [reg.sharedNetworks.proxy.name]: {
          aliases: [n.container('core')]
        },
      },
      labels: s.komodoSkip + s.proxy.add('komodo', 'komo', 9120),
    },

    [db]: {
      image: 'mongo:' + mongoVersion,
      container_name: n.container(db),  // referenced as komodo_db:27017 in core.env
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
    s.network.default   // private net (renamed default) 'komodo' — Core <-> mongo-db
    + s.network.join('proxy'),  // join shared-proxy (owned by traefik)
}
