local lib = import 'lib.libsonnet';

lib.Project {
  name:: 'komodo-mcp',
  envFiles:: [lib.Secret('komodoMcp')],

  app:: self.Service { role:: lib.collections.role.APP },
}
