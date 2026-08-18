local lib = import 'lib.libsonnet';

lib.Project {
  name:: 'garage',
  // No envFiles: garage runs on the NAS, outside the Komodo/Infisical ecosystem, so its
  // env file is hand-placed rather than agent-rendered — it is attached to the service in
  // services.jsonnet instead.

  app:: self.Service { role:: lib.role.APP },
}
