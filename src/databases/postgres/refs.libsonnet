local lib = import 'lib.libsonnet';

lib.Project {
  name:: 'postgres',
  envFiles:: [lib.Secret('postgres')],

  db:: self.Service { role:: lib.role.DB },
  dbData:: self.Volume { key:: 'db' },
}
