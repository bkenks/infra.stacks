local lib = import 'lib.libsonnet';

lib.Project {
  name:: 'stream',
  envFiles:: [lib.Secret('stream')],

  // Service keys are app names, not roles from lib.collections.role — nothing here is a generic
  // app/db/worker. All storage is host bind mounts, so this stack owns no volumes.
  bazarr:: self.Service { role:: 'bazarr' },
  configarr:: self.Service { role:: 'configarr' },
  decluttarr:: self.Service { role:: 'decluttarr' },
  plex:: self.Service { role:: 'plex' },
  prowlarr:: self.Service { role:: 'prowlarr' },
  radarr:: self.Service { role:: 'radarr' },
  sabnzbd:: self.Service { role:: 'sabnzbd' },
  seerr:: self.Service { role:: 'seerr' },
  sonarr:: self.Service { role:: 'sonarr' },
}
