local lib = import 'lib.libsonnet';
local refs = import 'refs.libsonnet';

local appVersion = 'latest';
local appPort = '7575';

local homarrUrl = 'https://' + lib.collections.domain.ktbcloud;
local authentik = lib.registry.endpoint.serviceGroup.authentik;
// Homarr is registered in authentik under its own name.
local issuer = authentik.proxy.oidc.issuer(refs.name);

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
        image: 'ghcr.io/homarr-labs/homarr:' + appVersion,
        restart: lib.collections.restart.unlessStopped,
        volumes: [
          refs.appData.mount('/appdata'),
          lib.collections.mounts.dockerSock,
        ],
        environment: {
          TZ: 'America/New_York',
          BASE_URL: homarrUrl,
          NEXTAUTH_URL: homarrUrl,
          SECRET_ENCRYPTION_KEY: '${SECRET_ENCRYPTION_KEY:?must provide encryption key}',

          AUTH_PROVIDERS: 'credentials,oidc',
          AUTH_OIDC_AUTO_LOGIN: '${AUTO_LOGIN:-true}',
          AUTH_OIDC_CLIENT_NAME: authentik.name,
          AUTH_OIDC_ISSUER: issuer,
          AUTH_OIDC_URI: authentik.proxy.oidc.uri,
          AUTH_LOGOUT_REDIRECT_URL: issuer + 'end-session/',
          AUTH_OIDC_SCOPE_OVERWRITE: 'openid email profile groups${EXTRA__OIDC_SCOPE:+ ${EXTRA__OIDC_SCOPE}}',
          AUTH_OIDC_GROUPS_ATTRIBUTE: '${OIDC_GROUP:-groups}',
          AUTH_OIDC_CLIENT_SECRET: '${AUTH_OIDC_CLIENT_SECRET}',
          AUTH_OIDC_CLIENT_ID: '${AUTH_OIDC_CLIENT_ID}',
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
