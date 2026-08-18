local lib = import 'lib.libsonnet';

lib.Project {
  name:: 'komodo-mcp',
  envFiles:: [lib.Secret('komodo-mcp')],

  app:: self.Service { role:: lib.role.APP },
}
