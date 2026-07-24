// The one import a stack needs: `local lib = import 'lib/lib.libsonnet';`
//
// Imports resolve through render.py's `-J <repo root>` jpath, so this path is the same
// from any depth under src/.
local compose = import 'lib/compose.libsonnet';

{
  registry:: import 'lib/registry.libsonnet',

  Service:: compose.Service,
  Stack:: compose.Stack,

  // Where infisical-agent renders a catalogue entry. Takes the catalogue KEY, never a
  // filename: the agent (producer, via templates/services.jsonnet) and the stack
  // (consumer, via env_file) derive the same path from the same entry, so they cannot
  // disagree — and a typo'd key fails at compile time instead of yielding a file nobody
  // writes. `dest` is not always '<key>.env' (komodo renders komodo_core.env) and not
  // always an env file at all (databasus renders a raw key), which is why it is looked up
  // rather than spelled out.
  Secret(key):: self.registry.secretPath + '/' + self.registry.infisical.catalog[key].dest,

  // The same file, for the stacks the control plane brings up before the agent exists to
  // render anything — bootstrap points them elsewhere and the default takes over after.
  SecretOrBootstrap(key):: '${ANSIBLE_SECRETS_FILE:-%s}' % self.Secret(key),

  // Marks a container so Komodo's StopAllContainers leaves it running.
  komodoSkip:: { 'komodo.skip': '' },

  // Splits a stack into the parent Compose file Komodo reads and the child holding the
  // stack itself, so env_file attaches at the include and the child stays portable.
  render(name, stack, envFiles=[])::
    local composeParent = 'compose.yaml';
    local composeChild = 'compose.stack.yaml';
    {
      [composeParent]: {
        name: name,
        include: [
          { path: composeChild }
          + (if std.length(envFiles) > 0 then { env_file: envFiles } else {}),
        ],
      },
      [composeChild]: stack,
    },

  // For entrypoints that render a bare env file rather than a compose stack.
  toEnv(o):: std.join('', ['%s=%s\n' % [k, o[k]] for k in std.objectFields(o)]),

  buildDataMount(storagePath, dataDir, internalPath):: '%s/%s:%s' % [storagePath, dataDir, internalPath],

  // Values for a service's `networks_`. Both take the network's real name on the host —
  // reference it through `registry.networks.shared.*` so producer and consumer cannot
  // disagree — and both render the top-level definition Stack() hoists.
  //
  // The split is ownership: exactly one stack `create`s a shared network, everyone else
  // `attach`es to it. Compose creates an `external` network for nobody, so a stack that
  // attaches to one that does not exist yet fails to come up instead of quietly building
  // its own empty copy.
  network:: {
    join(commonName)::    { [commonName]: {} },
    create(commonName)::  { [commonName]: { name: commonName } },
    attach(commonName)::  { [commonName]: { name: commonName, external: true } },
  },
}
