// DOCKER_VOLUMES comes from Komodo's own stack Environment.
local lib = import 'lib.libsonnet';
local refs = import 'refs.libsonnet';

local version = '2.1.2';
local mongoVersion = '8.2.4';
// Non-secret tunables, committed beside this file.
local coreEnv = './core.env';
local stackDir = lib.collections.dirs.docker.bindMounts + '/dcm';

{
  // What docker compose discovers. The include is where env_file goes: `${VAR:?err}` inside
  // services.yaml resolves from it, which a service-level env_file cannot do — that only
  // reaches the container's environment, never the compose document.
  compose: refs.compose,

  services: {
    name: refs.name,
    networks: { default: { name: refs.name } },
    volumes: refs.appData.declare,

    services: {
      [refs.app.key]: {
        container_name: refs.app.ext,
        image: 'ghcr.io/moghtech/komodo-core:' + version,
        restart: lib.collections.restart.unlessStopped,
        depends_on: [refs.db.key],
        volumes: [
          refs.appData.mount('/config/keys'),
          stackDir + '/komodo/data/backups:/backups',
          stackDir + '/komodo/data/syncs:/syncs',
        ],
        env_file: coreEnv,
        environment: {
          KOMODO_HOST: 'https://komo.' + lib.collections.domain.ktbinternal,
          KOMODO_DATABASE_USERNAME: '${KOMO_DB_USERNAME:?err}',
          KOMODO_DATABASE_PASSWORD: '${KOMO_DB_PASSWORD:?err}',
          KOMODO_WEBHOOK_SECRET: '${KOMO_WEBHOOK_SECRET:?err}',
          KOMODO_JWT_SECRET: '${KOMO_JWT_SECRET:?err}',
          // X25519 private key Core uses for the Noise handshake with every Periphery agent.
          // Set inline rather than left at the default `file:/config/keys/core.key`, so the
          // keypair is a managed secret instead of state in the komodo_app volume and
          // survives a rebuild. Agents pin the matching PUBLIC key (komodo_core_public_key in
          // infra.ansible group_vars) — rotating this means updating that too.
          KOMODO_PRIVATE_KEY: '${KOMO_PRIVATE_KEY:?err}',
        },
        // Published directly — the UI is reached via this port.
        ports: ['9120:9120'],
        init: true,
        // Komodo's own config already names the core komodo_core, so the alias keeps that
        // rather than following container_name.
        networks: { default: { aliases: [refs.name + '_core'] } },
        labels: lib.collections.labels.komodoSkip,
      },

      [refs.db.key]: {
        // Referenced as komodo_db in core.env.
        container_name: refs.db.ext,
        image: 'mongo:' + mongoVersion,
        restart: lib.collections.restart.unlessStopped,
        volumes: [
          stackDir + '/mongo/data:/data/db',
          stackDir + '/mongo/config:/data/configdb',
        ],
        env_file: coreEnv,
        environment: {
          MONGO_INITDB_ROOT_USERNAME: '${KOMO_DB_USERNAME:?err}',
          MONGO_INITDB_ROOT_PASSWORD: '${KOMO_DB_PASSWORD:?err}',
        },
        ports: ['27017:27017'],
        command: '--quiet --wiredTigerCacheSizeGB 0.25',
        labels: lib.collections.labels.komodoSkip,
      },
    },
  },
}
