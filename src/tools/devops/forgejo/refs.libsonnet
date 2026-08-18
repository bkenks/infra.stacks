local lib = import 'lib.libsonnet';

lib.Project {
  name:: 'forgejo',
  envFiles:: [lib.Secret('forgejo')],

  // Forgejo's own docs call it `server`, and the old stack did too.
  server:: self.Service { role:: lib.role.SERVER },
  db:: self.Service { role:: lib.role.DB },

  serverData:: self.Volume { key:: 'server' },
  dbData:: self.Volume { key:: 'db' },
}
