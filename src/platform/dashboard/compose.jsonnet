local lib = import 'lib/lib.libsonnet';
local reg = lib.registry;
local role = reg.role;

local name = 'homarr';

local httpScheme = 'https';
local homarrUrl = httpScheme + '://' + reg.domains.ktbcloud;

local authentik = reg.endpoint.authentik;
local authentikIssuerUri = authentik.public.oidc.issuer(name);

local appVersion = 'latest';
local appPort = 7575;

lib.render(
  name,
  lib.Stack(name, function(ref) {
    [role.APP]: lib.Service {
      image: 'ghcr.io/homarr-labs/homarr:' + appVersion,
      volumes_:: { app: '/appdata' },
      mounts_:: [reg.volumes.dockerSock.mount],
      environment: {
        // HOMARR //
        TZ:                       'America/New_York',
        BASE_URL:                 homarrUrl,
        NEXTAUTH_URL:             homarrUrl,
        // SECRETS
        SECRET_ENCRYPTION_KEY:    '${SECRET_ENCRYPTION_KEY:?must provide encryption key}',

        // OIDC //
        AUTH_PROVIDERS:             'credentials,oidc',
        AUTH_OIDC_AUTO_LOGIN:       '${AUTO_LOGIN:-true}',
        AUTH_OIDC_CLIENT_NAME:      authentik.name,
        AUTH_OIDC_ISSUER:           authentikIssuerUri,
        AUTH_OIDC_URI:              authentik.public.oidc.uri,
        AUTH_LOGOUT_REDIRECT_URL:   authentikIssuerUri + 'end-session/',
        AUTH_OIDC_SCOPE_OVERWRITE:  'openid email profile groups${EXTRA__OIDC_SCOPE:+ ${EXTRA__OIDC_SCOPE}}',
        AUTH_OIDC_GROUPS_ATTRIBUTE: '${OIDC_GROUP:-groups}',
        // Secrets
        AUTH_OIDC_CLIENT_SECRET:  '${AUTH_OIDC_CLIENT_SECRET}',
        AUTH_OIDC_CLIENT_ID:      '${AUTH_OIDC_CLIENT_ID}',
      },
      healthcheck: {
        test: ['CMD', 'curl', '-fsS', '--max-time', '2', 'http://localhost:' + std.toString(appPort)],
        interval: '30s',
        timeout: '10s',
        retries: 5,
      },
      expose: [std.toString(appPort)],
      ports: ['%s:18018:%s' % [reg.ips.loopback, appPort]],
    },
  }),
  [lib.Secret('homarr')],
)
