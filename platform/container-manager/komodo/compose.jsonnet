// komodo — Komodo Core (UI/control plane) + Mongo (config store).
//
// Source of truth: this file compiles to compose.yaml (do not edit the YAML).
// Names, aliases, versions, and the public domain come from this file or the
// shared registry. Only per-HOST runtime values stay as ${...} so docker
// compose interpolates them at deploy time.
local infra = import 'infra.libsonnet';
local reg = infra.registry;

local stack = 'komodo';
local n = infra.net.names(stack);

local version = '2.1.2';        // Komodo image tag (was interpolation var KOMO_VERS)
local mongoVersion = '8.2.4';
local vols = '${DOCKER_VOLUMES}';  // per-host volume root — runtime interpolated

{
  name: stack,

  services: {
    'komodo-core': {
      image: 'ghcr.io/moghtech/komodo-core:' + version,
      container_name: n.container('core'),
      depends_on: ['mongo-db'],
      volumes: [
        n.volume('keys') + ':/config/keys',  // auto-generated v2 PKI keys
        vols + '/dcm/komodo/data/backups:/backups',
        vols + '/dcm/komodo/data/syncs:/syncs',
      ],
      env_file: ['./core.env'],  // committed non-secret config (KOMODO_* tunables)
      environment: {
        // Public URL behind Traefik; built from the registry's root domain.
        KOMODO_HOST: 'https://komo.' + reg.rootDomain,
        // Secrets — interpolated from /dev/shm/komodo_core.env (parent include.env_file)
        KOMODO_DATABASE_USERNAME: '${KOMODO_DATABASE_USERNAME:?err}',
        KOMODO_DATABASE_PASSWORD: '${KOMODO_DATABASE_PASSWORD:?err}',
        KOMODO_WEBHOOK_SECRET: '${KOMODO_WEBHOOK_SECRET:?err}',
        KOMODO_JWT_SECRET: '${KOMODO_JWT_SECRET:?err}',
      },
      // 9120 published as a recovery fallback — Komodo manages Traefik, so don't
      // lock yourself out of the UI.
      ports: ['9120:9120'],
      extra_hosts: ['host.docker.internal:host-gateway'],
      restart: 'unless-stopped',
      init: true,
      networks: {
        default: { aliases: [n.alias('core')] },                       // talk to mongo-db
        [infra.net.netName('proxy')]: { aliases: [n.alias('core')] },  // expose to Traefik (shared-proxy)
      },
      labels: infra.mixins.komodoSkip + infra.mixins.proxyAdd('komodo', 'komo', 9120),
    },

    'mongo-db': {
      image: 'mongo:' + mongoVersion,
      container_name: 'mongo-db',  // referenced as mongo-db:27017 in core.env
      volumes: [
        vols + '/dcm/mongo/data:/data/db',
        vols + '/dcm/mongo/config:/data/configdb',
      ],
      env_file: ['./core.env'],  // committed non-secret config (shared with core)
      environment: {
        // Secrets — interpolated from /dev/shm/komodo_core.env (parent include.env_file)
        MONGO_INITDB_ROOT_USERNAME: '${MONGO_INITDB_ROOT_USERNAME:?err}',
        MONGO_INITDB_ROOT_PASSWORD: '${MONGO_INITDB_ROOT_PASSWORD:?err}',
      },
      ports: ['27017:27017'],
      command: '--quiet --wiredTigerCacheSizeGB 0.25',
      restart: 'unless-stopped',
      networks: {
        default: { aliases: [n.alias('mongo')] },
      },
      labels: infra.mixins.komodoSkip,
    },
  },

  volumes: {
    // Distinct from komodo-periphery's keys volume so PKI never cross-contaminates.
    [n.volume('keys')]: { name: n.volume('keys') },
  },

  networks:
    infra.net.default(stack)   // private net (renamed default) 'komodo' — Core <-> mongo-db
    + infra.net.join('proxy'),  // join shared-proxy (owned by traefik)
}
