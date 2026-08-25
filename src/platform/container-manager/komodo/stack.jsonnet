// DOCKER_VOLUMES comes from Komodo's own stack Environment.
local lib = import 'lib.libsonnet';
local refs = lib.Project {
  name:: 'komodo',

  app:: self.Service { role:: lib.collections.role.APP },
  db:: self.Service { role:: lib.collections.role.DB },
  appData:: self.Volume { key:: 'app' },
};

local version = '2.1.2';
local mongoVersion = '8.2.4';
// Non-secret tunables, committed beside this file.
local coreEnv = './core.env';
local stackDir = lib.collections.dirs.docker.bindMounts + '/dcm';

{
  compose: {
    name: refs.name,
    networks: { default: { name: refs.name } },
    volumes: refs.appData.declare,

    services: {
      [lib.collections.role.SECRETS]: lib.SecretsProvider('komodo'),

      [refs.app.key]: {
        container_name: refs.app.ext,
        image: 'ghcr.io/moghtech/komodo-core:' + version,
        restart: lib.collections.restart.unlessStopped,
        depends_on: lib.secretsReady {
          [refs.db.key]: { condition: lib.collections.condition.started },
        },
        volumes: [
          refs.appData.mount('/config/keys'),
          stackDir + '/komodo/data/backups:/backups',
          stackDir + '/komodo/data/syncs:/syncs',
        ],
        env_file: coreEnv,
        // KOMODO_DATABASE_USERNAME, KOMODO_DATABASE_PASSWORD, KOMODO_WEBHOOK_SECRET,
        // KOMODO_JWT_SECRET and KOMODO_PRIVATE_KEY all arrive from infisical-secrets. `db`
        // reads the same two database credentials as MONGO_INITDB_ROOT_USERNAME and
        // MONGO_INITDB_ROOT_PASSWORD, so the bundle carries them under both spellings.
        //
        // KOMODO_PRIVATE_KEY is the X25519 private key Core uses for the Noise handshake
        // with every Periphery agent. It is a managed secret rather than the default
        // `file:/config/keys/core.key`, so the keypair survives a rebuild of the komodo_app
        // volume. Agents pin the matching PUBLIC key (komodo_core_public_key in
        // infra.ansible group_vars) — rotating this means updating that too.
        environment: {
          KOMODO_HOST: 'https://komo.' + lib.collections.domain.ktbinternal,
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
        depends_on: lib.secretsReady,
        // MONGO_INITDB_ROOT_USERNAME and MONGO_INITDB_ROOT_PASSWORD arrive from
        // infisical-secrets, holding the same values `app` reads as KOMODO_DATABASE_*.
        ports: ['27017:27017'],
        command: '--quiet --wiredTigerCacheSizeGB 0.25',
        labels: lib.collections.labels.komodoSkip,
      },
    },
  },
}
