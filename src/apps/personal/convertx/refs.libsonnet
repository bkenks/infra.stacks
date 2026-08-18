local lib = import 'lib.libsonnet';

lib.Project {
  name:: 'convertx',
  envFiles:: [lib.Secret('convertx')],

  app:: self.Service { role:: lib.role.APP },
}
