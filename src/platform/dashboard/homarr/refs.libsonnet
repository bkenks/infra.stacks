local lib = import 'lib.libsonnet';

lib.Project {
  name:: 'homarr',
  envFiles:: [lib.Secret('homarr')],

  app:: self.Service { role:: lib.collections.role.APP },
  appData:: self.Volume { key:: 'app' },
}
