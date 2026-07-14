// forgejo: source-of-truth git forge (push-mirrors to GitHub). SSH via raw-TCP Traefik router on :22.
// `db` is dedicated Postgres, NOT shared-postgres.
local c = import 'compose.libsonnet';
local reg = import 'registry.libsonnet';
local secrets = reg.infisical.services;

local stack = 'forgejo';
local s = c.stack(stack);
local n = s.names;
local db = reg.roles.db;

// role name in compose is 'server' (matches the old stack + Forgejo's own docs).
local server = 'server';

local dbVersion = '14'; // docker.io/library/postgres
local port = 3000;

local dbUser = 'forgejo';
local dbName = 'forgejo';

local manifest = {
  name: stack,

  services: {
    [server]: {
      // Pinned to a fork image (codeberg upstream had issues) — do NOT revert to upstream.
      image: 'forgejoclone/forgejo:15',
      container_name: n.container(server),
      volumes: [
        server + ':/data',
        '/etc/localtime:/etc/localtime:ro',
      ],
      environment: {
        FORGEJO____APP_NAME: 'Forgejo',
        FORGEJO__database__DB_TYPE: 'postgres',
        FORGEJO__database__HOST: n.container(db) + ':5432',
        FORGEJO__database__NAME: dbName,
        FORGEJO__database__USER: dbUser,
        // Secret — interpolated from /dev/shm/forgejo.env (parent include.env_file)
        FORGEJO__database__PASSWD: '${DB_PASSWORD:?err}',
        USER_UID: '1000',
        USER_GID: '1000',
      },
      restart: 'on-failure:5',
      expose: [std.toString(port), '22'],
      networks: {
        default: { aliases: [n.container(server)] },
      },
      // 127.0.0.1:22 -> container SSH, dialed by bare-metal Newt (Pangolin edge on the VPS).
    } + c.publish(18003, port) + { ports+: c.publish(22, 22).ports },

    [db]: {
      image: 'docker.io/library/postgres:' + dbVersion,
      container_name: n.container(db),
      volumes: [db + ':/var/lib/postgresql/data'],
      environment: {
        POSTGRES_USER: dbUser,
        POSTGRES_DB: dbName,
        // Secret — interpolated from /dev/shm/forgejo.env (parent include.env_file)
        POSTGRES_PASSWORD: '${DB_PASSWORD:?err}',
      },
      restart: 'on-failure:5',
      networks: { default: { aliases: [n.container(db)] } },
      expose: ['5432'],
    },
  },

  volumes: {
    [server]: { name: n.volume(server) },
    [db]: { name: n.volume(db) },
  },

  networks:
    s.network.default,
};

c.render(stack, manifest, [secrets.forgejo.path])
