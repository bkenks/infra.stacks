// Helpers for building docker-compose fragments that reference the registry.
//
// Anything that names a registry entry takes the ENTRY, not a key into it —
// `join(reg.sharedNetworks.proxy)`, not `join('proxy')`. Both fail on a typo, but only
// the reference fails in the editor, before anything is rendered, and only the reference
// fails when the expression is never evaluated (jsonnet indexes lazily).
local r = import 'registry.libsonnet';

{
  stack(name):: {

    names: {
      stack:: name, // Project Name
      container(role):: name + '_' + role,
      volume(role):: name + '_' + role,
    },

    network: {

      join(net):: {
        [net.name]: {
          external: true,
          name: net.name
          }
        },

      own(net):: {
        [net.name]: {
          name: net.name
          }
        },

      // Takes a compose network NAME, not a registry entry — 'default' is a compose
      // concept with no registry counterpart.
      attach(network, alias) :: { [network]: { aliases: [ alias ] } },

      default:: { default: { name: name } },

    },

    proxy: {
      add(router, sub, port, zone=r.domains.ktbinternal):: {
        'traefik.enable': 'true',
        ['traefik.http.routers.' + router + '.rule']: 'Host(`' + sub + '.' + zone + '`)',
        ['traefik.http.routers.' + router + '.entrypoints']: 'websecure',
        ['traefik.http.routers.' + router + '.tls']: 'true',
        ['traefik.http.services.' + router + '.loadbalancer.server.port']: std.toString(port),
      },
      addAuth(router, sub, port, zone=r.domains.ktbinternal)::
        self.add(router, sub, port, zone) + {
          ['traefik.http.routers.' + router + '.middlewares']: 'authentik-forwardauth@file',
        },
    },

    // Marks a container so Komodo's StopAllContainers leaves it running.
    komodoSkip:: { 'komodo.skip': '' },
  },

  url(endpoint, scheme='http'):: {

    container::
      local e = endpoint.container;
      scheme + '://' + e.host + ':' + std.toString(e.port),

    public:: 'https://' + endpoint.public.sub + '.' + endpoint.public.domain,

  },


  // The two files every stack emits. compose.yaml is what Docker loads: the project name
  // and an include of the manifest. env_file paths are per-stack data — the registry does
  // not know them — and the key is omitted entirely for a stack with no secrets.
  render(name, manifest, envFiles=[]):: {
    'compose.yaml': {
      name: name,
      include: [
        { path: './compose.stack.yaml' }
        + (if std.length(envFiles) > 0 then { env_file: envFiles } else {}),
      ],
    },
    'compose.stack.yaml': manifest,
  },

  toEnv(o):: std.join('', [
  '%s=%s\n' % [k, o[k]] for k in std.objectFields(o)
  ]),
}
