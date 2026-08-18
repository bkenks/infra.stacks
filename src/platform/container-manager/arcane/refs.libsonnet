local lib = import 'lib.libsonnet';

lib.Project {
  name:: 'arcane',
  // Brought up by the control plane before the agent exists to render anything.
  envFiles:: [lib.SecretOrBootstrap('arcane')],

  app:: self.Service { role:: lib.role.APP },
  appData:: self.Volume { key:: 'app' },
}
