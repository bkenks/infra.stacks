local lib = import 'lib.libsonnet';

lib.Project {
  name:: 'terraria-tshock',

  app:: self.Service { role:: lib.role.APP },
}
