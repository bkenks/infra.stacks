local c = import 'compose.libsonnet';
local reg = import 'registry.libsonnet';
local secrets = reg.infisical.services;

local stack = 'pangolin-client';
local s = c.stack(stack);
local n = s.names;

local app = reg.roles.app;

local appVersion = 'latest';

local manifest = {
  name: stack,

  services: {
    // ── App: the user-facing service ────────────────────────────────────────────
    [app]: {
      image: 'fosrl/pangolin-cli:' + appVersion,
      container_name: n.container(app),
      environment: {
        PANGOLIN_ENDPOINT:    c.url(reg.endpoints.pangolin).pub,
        CLIENT_ID:            "${CLIENT_ID:?must provide a client id}",
        CLIENT_SECRET:        "${CLIENT_SECRET:?must provide a client secret}",
      },
      restart: reg.restartPolicy.defaultCritical,
      networks: s.network.attach("default", n.container(app)),
    }
  },

  networks:
    s.network.default,
};

c.render(stack, manifest, [secrets.pangolin_client.path])
