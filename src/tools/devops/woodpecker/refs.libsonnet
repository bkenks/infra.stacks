local lib = import 'lib.libsonnet';

lib.Project {
  name:: 'woodpecker',
  envFiles:: [lib.Secret('woodpecker')],

  server:: self.Service { role:: lib.collections.role.SERVER },
  agent:: self.Service { role:: lib.collections.role.AGENT },

  serverData:: self.Volume { key:: 'server' },
  agentData:: self.Volume { key:: 'agent' },
}
