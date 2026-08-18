local lib = import 'lib.libsonnet';

lib.Project {
  name:: 'file-brws-quantm',

  // One-shot: creates the directory tree and fixes its ownership before the app boots.
  init:: self.Service { role:: 'init' },
  app:: self.Service { role:: lib.role.APP },
}
