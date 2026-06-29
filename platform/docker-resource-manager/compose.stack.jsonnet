// docker-resource-manager — creates every shared Docker network in the registry, then exits.
//
// Source of truth: this file compiles to compose.stack.yaml (do not edit the YAML).
// A throwaway busybox attaches to every shared network (which forces compose to
// create them) and runs `true`. The networks persist after the container stops,
// so OWNER/CONSUMER stacks that reference them never race on a missing network.
// Deployed FIRST (see infra.ansible) so the shared nets exist before any other stack.
local lib = import 'lib.libsonnet';
local reg = lib.registry;

local stack = 'docker-resource-manager';
local n = lib.compose.names(stack);

local version = '1.37.0';

// Every shared-network key in the registry — iterate so adding a network there
// automatically extends this stack (no second list to keep in sync).
local netKeys = std.objectFields(reg.sharedNetworks);

{
  name: stack,

  services: {
    init: {
      image: 'docker.io/library/busybox:' + version,
      // Attach to every shared net so compose actually creates them, then exit 0.
      networks: { [lib.compose.netName(k)]: {} for k in netKeys },
      command: ['true'],
      restart: 'no',
    },
  },

  // OWN every shared network defined in the registry.
  networks: std.foldl(function(acc, k) acc + lib.compose.own(k), netKeys, {}),
}
