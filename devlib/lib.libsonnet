// The one import a stack needs: `local lib = import 'lib.libsonnet';`
//
// Imports resolve through render.py's `-J devlib` jpath, so this path is the same from any
// depth under src/.
//
// Nothing here builds compose objects. A stack's `compose:` field is plain Compose written
// against the ref table its own stack.jsonnet binds — what you read is what gets rendered.
// These are the values that cannot be written literally: the ones several places must agree
// on, and the secrets, which arrive at `up` rather than at render time.
local collections = import 'collections.libsonnet';
local registry = import 'registry.libsonnet';
local templates = import 'templates.libsonnet';

{
  // Raw constants: lib.collections.role, lib.collections.restart, ...
  collections:: collections,
  templates:: templates,

  // Every value one stack owns and another reads.
  registry:: registry,

  // The template a stack's `refs` table fills in.
  Project:: templates.Project,

  // The infisical-secrets compose provider, as a service. Takes the registry KEY, never a
  // project id and path: the catalog entry is the one place a bundle's location is written,
  // so a stack cannot drift from it, and a typo'd key fails at compile time.
  //
  // Every secret at that path is injected as a plain environment variable, under its own
  // Infisical name, into every service that declares depends_on on this one. There is no
  // compose-level interpolation left to rename or compose values with, so a secret must be
  // stored under exactly the name the container reads.
  SecretsProvider(key, recursive=true)::
    assert std.objectHasAll(registry.infisical.catalog, key) :
      'lib.SecretsProvider(%s): not in registry.infisical.catalog' % key;
    local bundle = registry.infisical.catalog[key];
    {
      provider: {
        type: 'infisical-secrets',
        options: {
          'credentials-file': registry.path.file.infisical_creds,
          domain: registry.infisical.address,
          'project-id': bundle.projectId,
          env: bundle.env,
          path: bundle.projectPath,
          recursive: recursive,
        },
      },
    },

  // The compose fragment every service reading those secrets needs. A provider has no
  // health of its own, so `started` is the only condition it can satisfy.
  secretsReady:: { [collections.role.SECRETS]: { condition: collections.condition.started } },

  // Where the control plane writes a secret bundle. Takes the registry KEY, never a
  // filename, so writer and reader derive the same path from the same entry and a typo'd
  // key fails at compile time instead of yielding a file nobody writes.
  //
  // Only the one stack the provider cannot serve still uses this: the Infisical server
  // itself, which would be asking itself for its own secrets before it is up.
  Secret(key)::
    assert std.objectHasAll(registry.infisical.catalog, key) :
      'lib.Secret(%s): not in registry.infisical.catalog' % key;
    registry.infisical.catalog[key].outFilePath,

  // The same file, overridable during bootstrap: the control plane points
  // ANSIBLE_SECRETS_FILE at wherever it wrote them, and the default takes over after.
  SecretOrBootstrap(key):: '${ANSIBLE_SECRETS_FILE:-%s}' % self.Secret(key),
}
