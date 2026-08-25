local lib = import 'lib.libsonnet';
local refs = lib.Project {
  name:: 'homarr',

  app:: self.Service { role:: lib.collections.role.APP },
  appData:: self.Volume { key:: 'app' },
};

local appVersion = 'latest';
local appPort = '7575';

local homarrUrl = 'https://' + lib.collections.domain.ktbcloud;
local authentik = lib.registry.endpoint.serviceGroup.authentik;
// Homarr is registered in authentik under its own name.
local issuer = authentik.proxy.oidc.issuer(refs.name);

{
  compose: {
    name: refs.name,
    networks: { default: { name: refs.name } },
    volumes: refs.appData.declare,

    services: {
      [lib.collections.role.SECRETS]: lib.SecretsProvider('infra', '/homarr'),

      [refs.app.key]: {
        container_name: refs.app.ext,
        image: 'ghcr.io/homarr-labs/homarr:' + appVersion,
        restart: lib.collections.restart.unlessStopped,
        depends_on: lib.secretsReady,
        volumes: [
          refs.appData.mount('/appdata'),
          lib.collections.mounts.dockerSock,
        ],
        // SECRET_ENCRYPTION_KEY, AUTH_OIDC_CLIENT_ID and AUTH_OIDC_CLIENT_SECRET arrive from
        // infisical-secrets. The three OIDC settings written literally below are the
        // defaults the old `${VAR:-default}` forms carried; a key of the same name in the
        // bundle overrides what is written here, so a per-host override still works.
        environment: {
          TZ: 'America/New_York',
          BASE_URL: homarrUrl,
          NEXTAUTH_URL: homarrUrl,

          AUTH_PROVIDERS: 'credentials,oidc',
          AUTH_OIDC_AUTO_LOGIN: 'true',
          AUTH_OIDC_CLIENT_NAME: authentik.name,
          AUTH_OIDC_ISSUER: issuer,
          AUTH_OIDC_URI: authentik.proxy.oidc.uri,
          AUTH_LOGOUT_REDIRECT_URL: issuer + 'end-session/',
          AUTH_OIDC_SCOPE_OVERWRITE: 'openid email profile groups',
          AUTH_OIDC_GROUPS_ATTRIBUTE: 'groups',
        },
        healthcheck: {
          test: ['CMD', 'curl', '-fsS', '--max-time', '2', 'http://localhost:' + appPort],
          interval: '30s',
          timeout: '10s',
          retries: 5,
        },
        expose: [appPort],
        ports: ['%s:18018:%s' % [lib.collections.ip.loopback, appPort]],
      },
    },
  },
}
