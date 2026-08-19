local lib = import 'lib.libsonnet';

lib.Project {
  name:: 'authentik',
  envFiles:: [lib.Secret('authentik')],

  app:: self.Service { role:: lib.collections.role.APP },
  worker:: self.Service { role:: lib.collections.role.WORKER },
  db:: self.Service { role:: lib.collections.role.DB },

  // Shared by app and worker; declared once, mounted twice.
  data:: self.Volume { key:: 'data' },
  dbData:: self.Volume { key:: 'db' },
}
