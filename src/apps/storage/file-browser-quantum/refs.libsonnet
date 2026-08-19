local lib = import 'lib.libsonnet';

lib.Project {
  name:: 'file-brws-quantm',

  app:: self.Service { role:: lib.collections.role.APP },
}
