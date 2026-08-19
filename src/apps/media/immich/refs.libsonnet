local lib = import 'lib.libsonnet';

lib.Project {
  name:: 'immich',
  envFiles:: [lib.Secret('immich')],

  // Immich's own upstream component names — no lib.collections.role equivalent.
  database:: self.Service { role:: 'database' },
  machineLearning:: self.Service { role:: 'machine-learning' },
  redis:: self.Service { role:: 'redis' },
  server:: self.Service { role:: lib.collections.role.SERVER },
}
