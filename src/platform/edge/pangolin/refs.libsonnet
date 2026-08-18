local lib = import 'lib.libsonnet';

lib.Project {
  name:: 'pangolin',
  envFiles:: [lib.Secret('pangolin'), lib.Secret('cfApiDnsToken')],

  // Only `init` takes the derived <project>_<role> name. The other three are dialled by
  // literal name from outside this stack — gerbil's own flags, the Traefik backends
  // Pangolin renders, and ops tooling — so each overrides container_name with its bare
  // role. All storage is a host bind mount, so this stack owns no volumes.
  init:: self.Service { role:: 'init' },
  pangolin:: self.Service { role:: 'pangolin', ext:: self.role },
  gerbil:: self.Service { role:: 'gerbil', ext:: self.role },
  traefik:: self.Service { role:: 'traefik', ext:: self.role },
}
