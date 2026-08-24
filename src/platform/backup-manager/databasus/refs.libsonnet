local lib = import 'lib.libsonnet';

lib.Project {
  name:: 'databasus',
  // No envFiles: databasus's only secret is a raw key file bind-mounted from the agent's
  // output directory, not an env file — see the mount in stack.jsonnet.

  app:: self.Service { role:: lib.collections.role.APP },
  appData:: self.Volume { key:: 'app' },
}
