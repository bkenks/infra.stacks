local c = import 'compose.libsonnet';
local reg = import 'registry.libsonnet';
local secrets = reg.infisical.services;

local stack = 'homarr';
local s = c.stack(stack);
local app = reg.roles.app;
local n = s.names;

local httpScheme = "https";
local cloudDomain = reg.domains.ktbcloud;
local homarr_fqdn = cloudDomain;
local homarr_url = httpScheme + "://" + homarr_fqdn;

local authentik_pub_ep = reg.endpoints.authentik.public;
local authentik_issuerUri = authentik_pub_ep.oidc.issuer(stack);

local appVersion = 'latest';

local appPort = 7575;

local manifest = {
  name: stack,

  services: {
    [app]: {
      image: 'ghcr.io/homarr-labs/homarr:' + appVersion,
      container_name: n.container(app),
      volumes: [n.volume(app) + ':/appdata', reg.volumes.dockerSock],
      environment: {
      // HOMARR //
        TZ:                       'America/New_York',
        BASE_URL:                 homarr_url,
        NEXTAUTH_URL:             homarr_url,
        // SECRETS
        SECRET_ENCRYPTION_KEY:    '${SECRET_ENCRYPTION_KEY:?must provide encryption key}',
        
      // OIDC //
        AUTH_PROVIDERS:             "credentials,oidc",
        AUTH_OIDC_AUTO_LOGIN:       "${AUTO_LOGIN:-true}",
        AUTH_OIDC_CLIENT_NAME:      reg.idp.name,
        AUTH_OIDC_ISSUER:           authentik_issuerUri,
        AUTH_OIDC_URI:              authentik_pub_ep.oidc.uri,
        AUTH_LOGOUT_REDIRECT_URL:   authentik_issuerUri + "end-session/",
        AUTH_OIDC_SCOPE_OVERWRITE:  std.toString("openid email profile groups${EXTRA__OIDC_SCOPE:+ ${EXTRA__OIDC_SCOPE}}"),
        AUTH_OIDC_GROUPS_ATTRIBUTE: "${OIDC_GROUP:-groups}",
        // Secrets
        AUTH_OIDC_CLIENT_SECRET:  "${AUTH_OIDC_CLIENT_SECRET}",
        AUTH_OIDC_CLIENT_ID:      "${AUTH_OIDC_CLIENT_ID}",
      },
      restart: 'unless-stopped',
      healthcheck: {
        test: ['CMD', 'curl', '-fsS', '--max-time', '2', 'http://localhost:' + std.toString(appPort)],
        interval: '30s',
        timeout: '10s',
        retries: 5,
      },
      networks: s.network.attach("default", n.container(app)),
      expose: [std.toString(appPort)],
    } + c.publish(18018, appPort),
  },

  volumes: {
    [n.volume(app)]: { name: n.volume(app) }
  },

  networks:
    s.network.default,
};

c.render(stack, manifest, [secrets.homarr.path])
