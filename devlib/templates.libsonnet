// The shapes a name can have. Nothing here holds a value — registry.libsonnet fills these
// in for anything crossing a stack boundary, and a stack's own refs.libsonnet fills
// `Project` in for the names it owns.
//
// A template exists where two files must agree on a string that neither should retype:
// `Endpoint.Public` is a scheme, a subdomain and a domain, so no one writes an URL by
// hand; `Project.Service` is a project and a role, so no one writes a container name.
{
  // A place something answers, described at the level it is reachable from.
  //
  //   Container  inside the compose project (or a shared docker network)
  //   Host       published on the host, dialled from another stack through the gateway
  //   Public     through the edge proxy, from the internet
  //
  // A service names only the levels it actually exposes.
  Endpoint:: {
    Container:: {
      scheme:: 'http',
      host:: error '"host" is required on Endpoint.Container',
      port:: error '"port" is required on Endpoint.Container',
      // —— derived ——
      addr:: '%s:%s' % [self.host, self.port],
      url:: '%s://%s' % [self.scheme, self.addr],
    },

    Host:: {
      scheme:: 'http',
      // The gateway name, so a consumer never spells it out; override for a host that
      // publishes somewhere else.
      host:: (import 'collections.libsonnet').hostGateway.host,
      port:: error '"port" is required on Endpoint.Host',
      // —— derived ——
      addr:: '%s:%s' % [self.host, self.port],
      url:: '%s://%s' % [self.scheme, self.addr],
    },

    Public:: {
      scheme:: 'https',
      sub:: error '"sub" is required on Endpoint.Public',
      domain:: error '"domain" is required on Endpoint.Public',
      // —— derived ——
      fqdn:: '%s.%s' % [self.sub, self.domain],
      url:: '%s://%s' % [self.scheme, self.fqdn],
    },
  },

  // A docker network several stacks share. Exactly one stack `create`s it and every other
  // `attach`es: compose builds an external network for nobody, so attaching before the
  // owner exists fails the deploy instead of quietly standing up a second empty copy.
  SharedNetwork:: { local network = self,
    base:: error '"base" is required on SharedNetwork',
    // —— derived ——
    name:: 'shared__' + self.base,
    create:: { [network.name]: { name: network.name } },
    attach:: { [network.name]: { name: network.name, external: true } },
  },

  // The names one stack owns. A stack's refs.libsonnet is this, filled in — see
  // src/templates/stack/refs.libsonnet.
  Project:: { local project = self,
    name:: error '"name" is required on Project',

    // Env files the include interpolates into services.yaml. `${VAR:?err}` in the manifest
    // resolves from these, which service-level `env_file:` cannot do — it only reaches the
    // container's environment, never the compose document. Build with lib.Secret(key).
    envFiles:: [],

    // What compose.yaml renders to. Every stack's compose.jsonnet is this one field, so the
    // project name and the env files are written once, in refs.libsonnet, and read twice.
    compose:: {
      name: project.name,
      include: [
        { path: 'services.yaml' }
        + (if project.envFiles == [] then {} else { env_file: project.envFiles }),
      ],
    },

    // The private bridge every service joins implicitly. `default` is compose's reserved
    // key, not a name; the stack's name lands underneath it.
    networks:: { default: { name: project.name } },

    Service:: {
      role:: error '"role" is required on Project.Service',
      // —— derived ——
      // The compose key, and the name every other service in the project dials: docker
      // resolves both the key and container_name on every network the container joins.
      key:: self.role,
      // What the container is called on the host, prefixed so it cannot collide with
      // another project's.
      container:: project.name + '_' + self.role,
    },

    Volume:: { local volume = self,
      key:: error '"key" is required on Project.Volume',
      // —— derived ——
      name:: project.name + '_' + self.key,
      // The top-level `volumes:` entry. Several services mounting one volume each write
      // `mount(...)`; only this declares it, so the two halves cannot drift.
      declare:: { [volume.key]: { name: volume.name } },
      mount(path):: '%s:%s' % [volume.key, path],
    },
  },
}
