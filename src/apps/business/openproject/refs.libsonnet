local lib = import 'lib.libsonnet';

lib.Project {
  name:: 'openproject',
  // The shared Postgres credentials come from the postgres bundle, not this stack's.
  envFiles:: [lib.Secret('openproject'), lib.Secret('postgres')],

  // One Rails image run four ways, plus a cache and a watchdog.
  web:: self.Service { role:: lib.collections.role.WEB },
  worker:: self.Service { role:: lib.collections.role.WORKER },
  seeder:: self.Service { role:: lib.collections.role.SEEDER },
  cron:: self.Service { role:: 'cron' },
  cache:: self.Service { role:: lib.collections.role.CACHE },
  autoheal:: self.Service { role:: 'autoheal' },
  hocuspocus:: self.Service { role:: 'hocuspocus' },

  // Mounted by all four Rails services; declared once.
  assets:: self.Volume { key:: 'assets' },
}
