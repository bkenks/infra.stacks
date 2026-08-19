local lib = import 'lib.libsonnet';

lib.Project {
  name:: 'paperless',
  envFiles:: [lib.Secret('paperless')],

  // Service keys are the upstream component names, not roles: nothing here is a generic
  // app/worker, and `webserver` is what paperless-ngx's own docs call it.
  broker:: self.Service { role:: 'broker' },
  db:: self.Service { role:: lib.collections.role.DB },
  gotenberg:: self.Service { role:: 'gotenberg' },
  tika:: self.Service { role:: 'tika' },
  webserver:: self.Service { role:: 'webserver' },

  brokerData:: self.Volume { key:: 'broker' },
  dbData:: self.Volume { key:: 'db' },
  webserverData:: self.Volume { key:: 'webserver_data' },
  webserverMedia:: self.Volume { key:: 'webserver_media' },
}
