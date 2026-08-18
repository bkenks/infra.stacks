local lib = import 'lib.libsonnet';

lib.Project {
  name:: 'komodo',
  // Brought up by the control plane before the agent exists to render anything. The bundle
  // renders to komodo_core.env, not komodo.env, so it cannot collide with the committed
  // ./core.env of non-secret tunables.
  envFiles:: [lib.SecretOrBootstrap('komodo')],

  app:: self.Service { role:: lib.role.APP },
  db:: self.Service { role:: lib.role.DB },
  appData:: self.Volume { key:: 'app' },
}
