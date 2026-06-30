// komodo — Komodo Core (UI/control plane) + Mongo (config store).
//
// Source of truth: this file compiles to compose.yaml (do not edit the YAML).
// Names, aliases, versions, and the public domain come from this file or the
// shared registry. Only per-HOST runtime values stay as ${...} so docker
// compose interpolates them at deploy time.
local lib = import 'lib.libsonnet';
local r = lib.registry;
local c = lib.compose;

// 

local stack = 'komodo';
local n = c.names(stack);
local app = c.roles.app;
local db = c.roles.db;

// 

local version = '2.1.2';        // Komodo image tag (was interpolation var KOMO_VERS)
local mongoVersion = '8.2.4';
local komodoEnv = './core.env';

{
  name: stack,

  services: {
    [app]: {
      image: 'ghcr.io/moghtech/komodo-core:' + version,
      container_name: n.container(app),
      depends_on: [ db ],
      volumes: [
        n.volume('keys') + ':/config/keys',  // auto-generated v2 PKI keys
        r.dockerVolumes + '/dcm/komodo/data/backups:/backups',
        r.dockerVolumes + '/dcm/komodo/data/syncs:/syncs',
      ],
      env_file: komodoEnv,  // committed non-secret config (KOMODO_* tunables)
      environment: {
        // Public URL behind Traefik; built from the registry's root domain.
        KOMODO_HOST: 'https://komo.' + r.domains.homektb,
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
          aliases: [n.alias('core')]
        },
        [lib.compose.netName('proxy')]: {
          aliases: [n.alias('core')]
        },
      },
      labels: lib.mixins.komodoSkip + lib.mixins.proxyAdd('komodo', 'komo', 9120),
    },

    [db]: {
      image: 'mongo:' + mongoVersion,
      container_name: n.container(db),  // referenced as komodo-db:27017 in core.env
      volumes: [
        r.dockerVolumes + '/dcm/mongo/data:/data/db',
        r.dockerVolumes + '/dcm/mongo/config:/data/configdb',
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
          aliases: [n.alias(db)]
        },
      },
      labels: lib.mixins.komodoSkip,
    },
  },

  volumes: {
    // Distinct from komodo-periphery's keys volume so PKI never cross-contaminates.
    [n.volume('keys')]: {
      name: n.volume('keys')
    },
    [n.volume(db)]: {
      name: n.volume(db),
    },
  },

  networks:
    n.network   // private net (renamed default) 'komodo' — Core <-> mongo-db
    + lib.compose.join('proxy'),  // join shared-proxy (owned by traefik)
}
