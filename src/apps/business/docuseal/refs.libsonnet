local lib = import 'lib.libsonnet';

lib.Project {
  name:: 'docuseal',
  // The shared Postgres credentials come from the postgres bundle, not this stack's.
  envFiles:: [lib.Secret('docuseal'), lib.Secret('postgres')],

  app:: self.Service { role:: lib.role.APP },
  appData:: self.Volume { key:: 'app' },
}
