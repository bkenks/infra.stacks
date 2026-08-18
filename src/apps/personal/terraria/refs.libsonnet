local lib = import 'lib.libsonnet';

lib.Project {
  name:: 'terraria',

  app:: self.Service { role:: lib.role.APP },
}
