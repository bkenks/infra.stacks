// A throwaway busybox attaches to every shared network (forcing compose to create them) then
// exits; the networks persist after, so OWNER/CONSUMER stacks never race on a missing network.
// Deployed FIRST (see infra.ansible) so the shared nets exist before any other stack.
// No secrets, no env_file: this stack only creates the shared networks and exits.
local c = import 'compose.libsonnet';
local reg = import 'registry.libsonnet';

local stack = 'docker-resource-manager';
local s = c.stack(stack);
local n = s.names;

local version = '1.37.0';

// Enumerate the registry so adding a network there auto-extends this stack (no list to
// sync). The keys come from objectFields, so nothing here can name a network that doesn't
// exist -- unlike a hand-written key, which is why every other stack references the entry.
local nets = [reg.sharedNetworks[k] for k in std.objectFields(reg.sharedNetworks)];

local manifest = {
  name: stack,

  services: {
    init: {
      image: 'docker.io/library/busybox:' + version,
      networks: { [net.name]: {} for net in nets },
      command: ['true'],
      restart: 'no',
    },
  },

  networks: std.foldl(function(acc, net) acc + s.network.own(net), nets, {}),
};

c.render(stack, manifest)
