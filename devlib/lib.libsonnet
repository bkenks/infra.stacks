// The one import a stack needs: `local lib = import 'lib.libsonnet';`
//
// Imports resolve through render.py's `-J devlib` jpath, so this path is the same from any
// depth under src/.
//
// There is deliberately nothing here that builds compose objects. A stack's services.jsonnet
// is plain Compose written against the ref table in its own refs.libsonnet — what you read
// is what gets rendered. These are the values that cannot be written literally because two
// different files have to agree on them.
local collections = import 'collections.libsonnet';
local registry = import 'registry.libsonnet';
local templates = import 'templates.libsonnet';

collections {
  registry:: registry,

  // The template a stack's refs.libsonnet fills in.
  Project:: templates.Project,

  // Where infisical-agent renders a secret bundle. Takes the registry KEY, never a
  // filename: the agent (producer) and the stack (consumer) derive the same path from the
  // same entry, so they cannot disagree — and a typo'd key fails at compile time instead of
  // yielding a file nobody writes.
  Secret(key)::
    assert std.objectHasAll(registry.secrets, key) :
      'lib.Secret(%s): not in registry.secrets' % key;
    '%s/%s' % [collections.dirs.secrets, registry.secrets[key]],

  // The same file, for the stacks the control plane brings up before the agent exists to
  // render anything — bootstrap points them elsewhere and the default takes over after.
  SecretOrBootstrap(key):: '${ANSIBLE_SECRETS_FILE:-%s}' % self.Secret(key),
}
