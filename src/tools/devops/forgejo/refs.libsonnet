local lib = import 'lib.libsonnet';

lib.Project {
  name:: 'forgejo',
  envFiles:: [lib.Secret('forgejo')],

  // Forgejo's own docs call it `server`, and the old stack did too.
  server:: self.Service { role:: lib.collections.role.SERVER },
  db:: self.Service { role:: lib.collections.role.DB },

  serverData:: self.Volume { key:: 'server' },
  dbData:: self.Volume { key:: 'db' },
}
