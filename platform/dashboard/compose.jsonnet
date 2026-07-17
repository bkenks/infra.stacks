local c = import 'compose.libsonnet';
local reg = import 'registry.libsonnet';
local secrets = reg.infisical.services;

local stack = 'homarr';
local s = c.stack(stack);
local app = reg.roles.app;
local n = s.names;

local appVersion = 'latest';

local appPort = 7575;

local manifest = {
  name: stack,

  services: {
    [app]: {
      image: 'ghcr.io/homarr-labs/homarr:' + appVersion,
      container_name: n.container(app),
      volumes: [n.volume(app) + ':/appdata'],
      environment: {
        SECRET_ENCRYPTION_KEY:    '${SECRET_ENCRYPTION_KEY:?must provide encryption key}',
        AUTH_PROVIDERS:           "credentials,oidc",
        AUTH_OIDC_ISSUER:         "${AUTH_OIDC_ISSUER}",
        AUTH_OIDC_CLIENT_SECRET:  "${AUTH_OIDC_CLIENT_SECRET}",
        AUTH_OIDC_CLIENT_ID:      "${AUTH_OIDC_CLIENT_ID}",
        AUTH_OIDC_CLIENT_NAME:    reg.idp.name,
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
