// forgejo: source-of-truth git forge (push-mirrors to GitHub). SSH via a raw-TCP Traefik
// router on :22. `db` is a dedicated Postgres, NOT the shared cluster.
local lib = import 'lib.libsonnet';
local refs = import 'refs.libsonnet';

// Pinned to a fork image (codeberg upstream had issues) — do NOT revert to upstream.
local serverImage = 'forgejoclone/forgejo:15';
local dbVersion = '14';
local port = '3000';
local dbUser = refs.name;
local dbName = refs.name;
local sharedDB = lib.registry.network.shared.forgejoDB;

{
  name: refs.name,
  networks: {
    default: { name: refs.name },
    [sharedDB.name]: { name: sharedDB.name, external: true },
  },
  volumes: refs.serverData.declare + refs.dbData.declare,

  services: {
    [refs.server.key]: {
      container_name: refs.server.ext,
      image: serverImage,
      restart: lib.restart.onFailure(5),
      volumes: [
        refs.serverData.mount('/data'),
        '/etc/localtime:/etc/localtime:ro',
      ],
      environment: {
        FORGEJO____APP_NAME: 'Forgejo',
        FORGEJO__database__DB_TYPE: 'postgres',
        FORGEJO__database__HOST: refs.db.key + ':5432',
        FORGEJO__database__NAME: dbName,
        FORGEJO__database__USER: dbUser,
        FORGEJO__database__PASSWD: '${DB_PASSWORD:?err}',
        USER_UID: '1000',
        USER_GID: '1000',
      },
      expose: [port, '22'],
      // 127.0.0.1:22 -> container SSH, dialled by bare-metal Newt (Pangolin edge on the VPS).
      ports: [
        '%s:18003:%s' % [lib.ip.loopback, port],
        '%s:22:22' % lib.ip.loopback,
      ],
    },

    [refs.db.key]: {
      container_name: refs.db.ext,
      image: 'docker.io/library/postgres:' + dbVersion,
      restart: lib.restart.onFailure(5),
      networks: ['default', sharedDB.name],
      volumes: [refs.dbData.mount('/var/lib/postgresql/data')],
      environment: {
        POSTGRES_USER: dbUser,
        POSTGRES_DB: dbName,
        POSTGRES_PASSWORD: '${DB_PASSWORD:?err}',
      },
      expose: ['5432'],
      ports: ['%s:18041:5432' % lib.ip.loopback],
    },
  },
}
