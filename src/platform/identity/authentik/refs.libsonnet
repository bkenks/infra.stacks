local lib = import 'lib.libsonnet';

lib.Project {
  name:: 'authentik',
  envFiles:: [lib.Secret('authentik')],

  app:: self.Service { role:: lib.role.APP },
  worker:: self.Service { role:: lib.role.WORKER },
  db:: self.Service { role:: lib.role.DB },

  // Shared by app and worker; declared once, mounted twice.
  data:: self.Volume { key:: 'data' },
  dbData:: self.Volume { key:: 'db' },
}
