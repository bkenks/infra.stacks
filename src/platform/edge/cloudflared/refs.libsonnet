local lib = import 'lib.libsonnet';

lib.Project {
  name:: 'cloudflared',
  // Brought up by the control plane before the agent exists to render anything.
  envFiles:: [lib.SecretOrBootstrap('cloudflared')],

  tunnel:: self.Service { role:: lib.role.TUNNEL },
}
