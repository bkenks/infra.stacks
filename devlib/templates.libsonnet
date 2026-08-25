// The shapes a name can have. Nothing here holds a value — registry.libsonnet fills these
// in for anything crossing a stack boundary, and a stack's own `refs` table fills
// `Project` in for the names it owns.
{
  Endpoint:: {
    // The host inventory. Every host runs CoreDNS for the zone, so host-to-host traffic is
    // dialled by name — there are no IPs here.
    HostGroup:: { local hostGroup = self,
      zone::
        error '"zone" is a required field',
      Host:: {
        alias::
          error '"alias" is a required field',
        ref::
          self.alias + '.' + hostGroup.zone,
      },
    },

    // A place a service answers, described at the level it is reachable from.
    //
    //   Container  container-to-container, on this host, over a shared docker network
    //   Host       host-to-host, over the .internal zone
    //   Proxy      from the internet, through the edge proxy
    //
    // A service names only the levels it actually exposes.
    ServiceGroup:: {
      Service:: {
        Container:: {
          name::
            error '"name" is a required field of template "Container"',
          port::
            error '"port" is a required field of template "Container"',
          scheme::
            'http',
          addr::
            '%s:%s' % [self.name, self.port],
          url(scheme=self.scheme, name=self.name, port=self.port)::
            '%s://%s:%s' % [scheme, name, port],
        },

        Host:: {
          // The HostGroup entry that publishes this port. Which host runs a service is a
          // fact about that stack, so it is single-sourced here rather than retyped by
          // every consumer.
          on::
            error '"on" is a required field of template "Host"',
          port::
            error '"port" is a required field of template "Host"',
          scheme::
            'http',
          addr::
            '%s:%s' % [self.on.ref, self.port],
          url::
            '%s://%s' % [self.scheme, self.addr],
        },

        Proxy:: {
          subdomain::
            error '"subdomain" is a required field of "Proxy"',
          domain::
            error '"domain" is a required field of "Proxy"',
          scheme::
            'https',
          fqdn::
            '%s.%s' % [self.subdomain, self.domain],
          url::
            '%s://%s' % [self.scheme, self.fqdn],
        },
      },
    },
  },

  // A docker network several stacks on the same host share. It is created out of band and
  // every participating stack declares it `external`.
  SharedNetwork:: {
    base::
      error '"base" is required on SharedNetwork',
    name::
      'shared__' + self.base,
  },

  // The names one stack owns. A stack's `refs` table is this, filled in.
  Project:: { local project = self,
    name::
      error '"name" is required on Project',

    // Env files the include interpolates into services.yaml, built with lib.Secret(key).
    // Only the Infisical server's own stack still needs this — every other stack reads its
    // secrets through lib.SecretsProvider, which injects them at `up` instead. Left empty,
    // the stack renders a single compose document and no include.
    envFiles:: [],

    // What compose.yaml renders to. Every stack's `compose:` field is exactly this.
    compose:: {
      name: project.name,
      include: [
        { path: 'services.yaml' }
        + (if project.envFiles == [] then {} else { env_file: project.envFiles }),
      ],
    },

    Service:: {
      role::
        error '"role" is required on Project.Service',
      // The compose key, and the name every other service in the project dials.
      key:: self.role,
      // What the container is called on the host, prefixed so it cannot collide with
      // another project's.
      ext:: project.name + '_' + self.role,
    },

    Volume:: { local volume = self,
      key::
        error '"key" is required on Project.Volume',
      name::
        project.name + '_' + self.key,
      declare:: { [volume.key]: { name: volume.name } },
      mount(path):: '%s:%s' % [volume.key, path],
    },
  },
}
