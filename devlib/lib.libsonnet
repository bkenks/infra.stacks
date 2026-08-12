// The one import a stack needs: `local lib = import 'lib.libsonnet';`
//
// Imports resolve through render-compose.py's `-J` jpath, so this path is the same from any
// depth under src/.
//
// There is deliberately nothing here that builds compose objects. A stack file is plain
// Compose, written against the ref table in its own refs.libsonnet — what you read is what
// gets rendered. These are the handful of values that cannot be written literally because
// two different files have to agree on them.

{
  collections:: import 'collections.libsonnet',

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

  // For entrypoints that render a bare env file rather than a compose document.
  toEnv(o):: std.join('', ['%s=%s\n' % [k, o[k]] for k in std.objectFields(o)]),
}
