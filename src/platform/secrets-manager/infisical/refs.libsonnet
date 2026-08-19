local lib = import 'lib.libsonnet';

lib.Project {
  name:: 'infisical',
  // The server is bootstrapped by Ansible — it cannot read its own secrets through the
  // agent before the agent exists.
  envFiles:: [lib.SecretOrBootstrap('infisical')],

  app:: self.Service { role:: lib.collections.role.APP },
  db:: self.Service { role:: lib.collections.role.DB },
  // `redis` rather than lib.collections.role.CACHE: the container name is what other things on the
  // host already know it by.
  redis:: self.Service { role:: 'redis' },
  agent:: self.Service { role:: lib.collections.role.AGENT },

  dbData:: self.Volume { key:: 'db' },
  redisData:: self.Volume { key:: 'redis' },
}
