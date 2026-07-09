// Helpers for building docker-compose fragments that reference the registry.
local r = import 'registry.libsonnet';
local sharedNetworks = r.sharedNetworks;

{
  stack(name):: {

    names: {
      stack:: name, // Project Name
      container(role):: name + '_' + role,
      volume(role):: name + '_' + role,
    },

    network: {

      join(key):: {
        [sharedNetworks[key].name]: {
          external: true,
          name: sharedNetworks[key].name
          }
        },

      own(key):: {
        [sharedNetworks[key].name]: {
          name: sharedNetworks[key].name
          }
        },

      attach(network, alias) :: { [network]: { aliases: [ alias ] } },

      default:: { default: { name: name } },
      
    },

    proxy: {
      add(router, sub, port, domain=r.domains.ktbinternal)::
        // domain may be a registry key ('stackform') or a literal zone; resolve if the former.
        local zone = if std.objectHas(r.domains, domain) then r.domains[domain] else domain;
        {
          'traefik.enable': 'true',
          ['traefik.http.routers.' + router + '.rule']: 'Host(`' + sub + '.' + zone + '`)',
          ['traefik.http.routers.' + router + '.entrypoints']: 'websecure',
          ['traefik.http.routers.' + router + '.tls']: 'true',
          ['traefik.http.services.' + router + '.loadbalancer.server.port']: std.toString(port),
        },
      addAuth(router, sub, port, domain=r.domains.ktbinternal)::
        self.add(router, sub, port, domain) + {
          ['traefik.http.routers.' + router + '.middlewares']: 'authentik-forwardauth@file',
        },
    },

    // Marks a container so Komodo's StopAllContainers leaves it running.
    komodoSkip:: { 'komodo.skip': '' },
  },

  url(key, scheme='http'): {

    container::
      local e = r.endpoints[key].container;
      scheme + '://' + e.host + ':' + std.toString(e.port),

    public:: 'https://' + r.endpoints[key].public.sub + '.' + r.endpoints[key].public.domain,

  },

  envPath: {
    secret(envFilename): '/dev/shm/' + envFilename,
    platform(envFilename):: '${ANSIBLE_SECRETS_FILE:-' + self.secret(envFilename) + '}',
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
}
