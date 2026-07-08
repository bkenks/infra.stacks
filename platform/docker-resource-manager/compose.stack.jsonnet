// A throwaway busybox attaches to every shared network (forcing compose to create them) then
// exits; the networks persist after, so OWNER/CONSUMER stacks never race on a missing network.
// Deployed FIRST (see infra.ansible) so the shared nets exist before any other stack.
local c = import 'compose.libsonnet';
local reg = import 'registry.libsonnet';

local stack = 'docker-resource-manager';
local s = c.stack(stack);
local n = s.names;

local version = '1.37.0';

// Iterate registry keys so adding a network there auto-extends this stack (no list to sync).
local netKeys = std.objectFields(reg.sharedNetworks);

{
  name: stack,

  services: {
    init: {
      image: 'docker.io/library/busybox:' + version,
      networks: { [reg.sharedNetworks[k].name]: {} for k in netKeys },
      command: ['true'],
      restart: 'no',
    },
  },

  networks: std.foldl(function(acc, k) acc + s.network.own(k), netKeys, {}),
}
