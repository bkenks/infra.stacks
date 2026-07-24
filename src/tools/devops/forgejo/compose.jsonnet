// forgejo: source-of-truth git forge (push-mirrors to GitHub). SSH via raw-TCP Traefik router on :22.
// `db` is dedicated Postgres, NOT shared-postgres.
local lib = import 'lib/lib.libsonnet';
local reg = lib.registry;
local role = reg.role;

local name = 'forgejo';
local dbVersion = '14'; // docker.io/library/postgres
local port = 3000;

local dbUser = 'forgejo';
local dbName = 'forgejo';

lib.render(
  name,
  lib.Stack(name, function(ref) {
    // role in compose is 'server' (matches the old stack + Forgejo's own docs).
    [role.SERVER]: lib.Service {
      // Pinned to a fork image (codeberg upstream had issues) — do NOT revert to upstream.
      image: 'forgejoclone/forgejo:15',
      volumes_:: { server: '/data' },
      mounts_:: ['/etc/localtime:/etc/localtime:ro'],
      environment: {
        FORGEJO____APP_NAME: 'Forgejo',
        FORGEJO__database__DB_TYPE: 'postgres',
        FORGEJO__database__HOST: ref[role.DB] + ':5432',
        FORGEJO__database__NAME: dbName,
        FORGEJO__database__USER: dbUser,
        // Secret — interpolated from /dev/shm/forgejo.env (parent include.env_file)
        FORGEJO__database__PASSWD: '${DB_PASSWORD:?err}',
        USER_UID: '1000',
        USER_GID: '1000',
      },
      restart: 'on-failure:5',
      expose: [std.toString(port), '22'],
      // 127.0.0.1:22 -> container SSH, dialed by bare-metal Newt (Pangolin edge on the VPS).
      ports: [
        '%s:18003:%s' % [reg.ips.loopback, port],
        '%s:22:22' % reg.ips.loopback,
      ],
    },

    [role.DB]: lib.Service {
      image: 'docker.io/library/postgres:' + dbVersion,
      volumes_:: { db: '/var/lib/postgresql/data' },
      environment: {
        POSTGRES_USER: dbUser,
        POSTGRES_DB: dbName,
        // Secret — interpolated from /dev/shm/forgejo.env (parent include.env_file)
        POSTGRES_PASSWORD: '${DB_PASSWORD:?err}',
      },
      restart: 'on-failure:5',
      expose: ['5432'],
      ports: [reg.ips.loopback + ":18041:5432"],
      networks_:: lib.network.join(reg.networks.shared.forgejoDB),
    },
  }, lib.network.create(reg.networks.shared.forgejoDB)),
  [lib.Secret('forgejo')],
)
