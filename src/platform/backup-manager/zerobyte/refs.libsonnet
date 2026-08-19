local lib = import 'lib.libsonnet';

lib.Project {
  name:: 'zerobyte',
  // Brought up by the control plane before the agent exists to render anything.
  envFiles:: [lib.SecretOrBootstrap('zerobyte')],

  app:: self.Service { role:: lib.collections.role.APP },
  appData:: self.Volume { key:: 'app' },
}
