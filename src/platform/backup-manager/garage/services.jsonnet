// Garage — single-node S3 object storage, the restic repository zerobyte and databasus
// push to. Runs on the NAS: no periphery agent deploys it and no Infisical agent renders
// its secrets.
//
// The image declares no ENTRYPOINT (CMD is ["/garage","server"]), so `command` has to
// repeat the binary path — args alone would be dropped. Without --single-node the node
// never assigns itself a layout and sits refusing S3 requests, and every GARAGE_DEFAULT_*
// is silently ignored. --default-bucket implies --default-access-key; both require
// --single-node.
local lib = import 'lib.libsonnet';
local refs = import 'refs.libsonnet';

local appVersion = 'v2.3.0';
local garageDir = lib.dirs.nas.backups + '/s3_garage';

// Garage's own ports. Only these two are published: 3901 is cluster RPC, which a single
// node never needs reachable, and 3902 is the static-website endpoint, which a backup
// repository has no use for.
local s3Port = '3900';
local adminPort = '3903';

{
  name: refs.name,
  networks: refs.networks,

  services: {
    [refs.app.key]: {
      container_name: refs.app.container,
      image: 'dxflrs/garage:' + appVersion,
      restart: lib.restart.unlessStopped,
      command: ['/garage', 'server', '--single-node', '--default-bucket'],
      ports: [
        '18900:' + s3Port,
        '18903:' + adminPort,
      ],
      volumes: [
        './garage.toml:/etc/garage.toml:ro',
        garageDir + '/meta:/var/lib/garage/meta',
        garageDir + '/data:/var/lib/garage/data',
      ],
      env_file: ['%s/garage/%s.env' % [lib.dirs.nas.docker, refs.name]],
      // `garage status` dials the daemon over RPC and picks the secret out of the service
      // environment, so it needs nothing the container does not already have. start_period
      // covers the first-boot layout assignment, which runs before the API is listening.
      healthcheck: {
        test: ['CMD', '/garage', 'status'],
        interval: '30s',
        timeout: '5s',
        retries: 3,
        start_period: '15s',
      },
    },
  },
}
