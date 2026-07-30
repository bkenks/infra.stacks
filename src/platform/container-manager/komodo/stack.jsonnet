// env_file komodo_core.env supplies KOMODO_*/MONGO_* secrets; named to avoid colliding with
// the committed ./core.env (non-secret tunables). DOCKER_VOLUMES comes from Komodo's stack Environment.
local lib = import 'lib/lib.libsonnet';
local reg = lib.registry;
local role = reg.role;

local name = 'komodo';
local version = '2.1.2';
local mongoVersion = '8.2.4';
local komodoEnv = './core.env';
local stackDir = reg.dirs.docker.root + '/bind-mounts/dcm';

lib.render(
  name,
  lib.Stack(name, function(ref) {
    [role.APP]: lib.Service {
      image: 'ghcr.io/moghtech/komodo-core:' + version,
      depends_on: [role.DB],
      volumes_:: { app: '/config/keys' },
      mounts_:: [
        stackDir + '/komodo/data/backups:/backups',
        stackDir + '/komodo/data/syncs:/syncs',
      ],
      env_file: komodoEnv,
      environment: {
        KOMODO_HOST: 'https://komo.' + reg.domains.ktbinternal,
        // Secrets — interpolated from /dev/shm/komodo_core.env (parent include.env_file)
        KOMODO_DATABASE_USERNAME: '${KOMO_DB_USERNAME:?err}',
        KOMODO_DATABASE_PASSWORD: '${KOMO_DB_PASSWORD:?err}',
        KOMODO_WEBHOOK_SECRET: '${KOMO_WEBHOOK_SECRET:?err}',
        KOMODO_JWT_SECRET: '${KOMO_JWT_SECRET:?err}',
        // X25519 private key Core uses for the Noise handshake with every
        // Periphery agent. Set inline rather than left at the default
        // `file:/config/keys/core.key`, so the keypair is a managed secret
        // instead of state in the komodo_app volume and survives a rebuild.
        // Agents pin the matching PUBLIC key (komodo_core_public_key in
        // infra.ansible group_vars) — rotating this means updating that too.
        KOMODO_PRIVATE_KEY: '${KOMO_PRIVATE_KEY:?err}',
      },
      // Published directly — the UI is reached via this exposed port.
      ports: ['9120:9120'],
      extra_hosts: ['host.docker.internal:host-gateway'],
      init: true,
      // Komodo's own config already names the core komodo_core, so the alias keeps that
      // rather than following container_name.
      networks: { default: { aliases: [name + '_core'] } },
      labels: lib.komodoSkip,
    },

    [role.DB]: lib.Service {
      image: 'mongo:' + mongoVersion,
      // referenced as komodo_db in core.env
      mounts_:: [
        stackDir + '/mongo/data:/data/db',
        stackDir + '/mongo/config:/data/configdb',
      ],
      env_file: komodoEnv,
      environment: {
        // Secrets — interpolated from /dev/shm/komodo_core.env (parent include.env_file)
        MONGO_INITDB_ROOT_USERNAME: '${KOMO_DB_USERNAME:?err}',
        MONGO_INITDB_ROOT_PASSWORD: '${KOMO_DB_PASSWORD:?err}',
      },
      ports: ['27017:27017'],
      command: '--quiet --wiredTigerCacheSizeGB 0.25',
      labels: lib.komodoSkip,
    },
  }),
  [lib.SecretOrBootstrap('komodo')],
)
