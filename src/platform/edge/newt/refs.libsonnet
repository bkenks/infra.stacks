local lib = import 'lib.libsonnet';

lib.Project {
  name:: 'newt',
  envFiles:: [lib.Secret('newt')],

  tunnel:: self.Service { role:: lib.role.TUNNEL },
}
