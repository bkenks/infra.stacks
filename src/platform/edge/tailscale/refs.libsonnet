local lib = import 'lib.libsonnet';

lib.Project {
  name:: 'ts-dokr-gw',
  envFiles:: [lib.Secret('tsGateway')],

  app:: self.Service { role:: lib.collections.role.APP },
  appData:: self.Volume { key:: 'app' },
}
