// Reads /var/lib/docker/volumes off the host through a bind mount, like zerobyte, so it
// owns no shared network. Repositories and their credentials are entered in the UI and
// kept in config.json on the config volume, so there is no secret bundle to pull and no
// bootstrap document to carry one.
local lib = import 'lib.libsonnet';
local refs = lib.Project {
  name:: 'backrest',

  app:: self.Service { role:: lib.collections.role.APP },
  data:: self.Volume { key:: 'data' },
  config:: self.Volume { key:: 'config' },
  cache:: self.Volume { key:: 'cache' },
  tmp:: self.Volume { key:: 'tmp' },
  rclone:: self.Volume { key:: 'rclone' },
};

local version = 'v1.14.1';
local port = '9898';

{
  compose: {
    name: refs.name,
    networks: { default: { name: refs.name } },
    volumes: refs.data.declare + refs.config.declare + refs.cache.declare + refs.tmp.declare + refs.rclone.declare,

    services: {
      [refs.app.key]: {
        container_name: refs.app.ext,
        // Backrest identifies this instance by its hostname; pinned so a recreate does not
        // hand it a fresh container id and a new identity.
        hostname: refs.name,
        image: 'ghcr.io/garethgeorge/backrest:' + version,
        restart: lib.collections.restart.unlessStopped,
        volumes: [
          refs.data.mount('/data'),
          refs.config.mount('/config'),
          refs.cache.mount('/cache'),
          // restic stages large files under TMPDIR; a volume keeps them off the overlay.
          refs.tmp.mount('/tmp'),
          // Only read when a repository uses an rclone remote.
          refs.rclone.mount('/root/.config/rclone'),
          '/var/lib/docker/volumes:/userdata',
        ],
        environment: {
          BACKREST_DATA: '/data',
          BACKREST_CONFIG: '/config/config.json',
          XDG_CACHE_HOME: '/cache',
          TMPDIR: '/tmp',
          TZ: 'America/New_York',
        },
        // Core infra, no proxy in front of it.
        ports: [port + ':' + port],
      },
    },
  },
}
