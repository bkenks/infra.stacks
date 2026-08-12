{
  Endpoint:: {
    HostGroup:: { local hostGroup = self,
      zone:: error '"zone" is a required field',
      Host:: {
        alias:: error '"alias" is a required field',
        ref:: self.alias + "." + hostGroup.internal,
      }
    },

    ServiceGroup:: {
      Service:: {
        Container:: {
          name:: error '"name" is a required field of template "Container"',
          port:: error '"port" is a required field of template "Container"',
          portMap:: { port:: '', type:: ''}, // For services with more than one port; "type" = purpose of port (e.g. web, backend, etc)
          scheme:: 'http',
          // —— calculated ——
          url(scheme=self.scheme, name=self.name, port=self.port)::
            '%s://%s:%s' % [scheme, name, port],
        },
        Host:: {
          // name:: '', // TODO: delete this if never referenced
          port:: error '"port" is a required field of template "Host"',
          // portMap:: { port:: '', type:: ''}, // TODO: delete this if never referenced
          // scheme:: 'http', // TODO: delete this if never referenced
          // —— calculated ——
          // url(scheme=self.scheme, name=self.name, port=self.port):: // TODO: delete this if never referenced
          //   '%s://%s:%s' % [scheme, name, port],
        },
        Proxy:: {
          subdomain:: error '"subdomain" is a required field of "Proxy"',
          domain::    error '"domain" is a required field of "Proxy"',
          scheme:: 'https',
          // —— calculated ——
          fqdn:: '%s.$s' % [self.subdomain, self.domain],
          url:: '%s://%s' % [self.scheme, self.fqdn],
        },
      }
    }
  },

  Network:: {
    Shared:: { local network = self,
      local prefix = 'shared__',
      name_:: error 'name_:: is required',
      name:: prefix + self.name_,
      ref(alias=''):: if std.isEmpty(alias) then network.name else { [network.name]: {alias: alias} },
      def:: {
        [network.name]: { name: network.name, external: true },
      },
    },
  },

  Project:: { local project = self,
    name:: error '"name" is a required field of "Project"',

    Network:: {},
    
    Volume:: { local volume = self,
      name:: error '"name" is a required field of "Volume"',
      relatedRole:: error '"relatedRole" is a required field of "Volume" | e.g. "app", "db", "web"',
      ref:: {
        compose:: volume.relatedRole_ + "_" + volume.name_,
        ext::     project.name + "_" + volume.relatedRole_ + "_" + volume.name_,
      }
    },

    Service:: { local service = self,
      role:: error '"role" is a required field of "Service"',
      ref:: {
        compose:: service.role,
        ext::     project.name + "_" + service.role,
      }
    }
  }
}