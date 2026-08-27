// The one import a stack needs: `local lib = import 'lib.libsonnet';`
//
// Imports resolve through render.py's `-J devlib -J src` jpath, so this path is the same
// from any depth under src/. `registry.libsonnet` is the repo's own, at src/.
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

  // The infisical-secrets compose provider, as a service. `project` is a KEY into
  // registry.infisical.project, so a typo fails at compile time rather than fetching from
  // nowhere; `path` is the bundle's folder, written here because exactly one stack reads it.
  //
  // Every secret at that path is injected as a plain environment variable, under its own
  // Infisical name, into every service that declares depends_on on this one. There is no
  // compose-level interpolation left to rename or compose values with, so a secret must be
  // stored under exactly the name the container reads.
  SecretsProvider(project, path, env='prod', recursive=true)::
    assert std.objectHasAll(registry.infisical.project, project) :
      'lib.SecretsProvider(%s): not in registry.infisical.project' % project;
    {
      provider: {
        type: 'infisical-secrets',
        options: {
          'credentials-file': registry.path.file.infisical_creds,
          domain: registry.infisical.address,
          'project-id': registry.infisical.project[project],
          env: env,
          path: path,
          recursive: recursive,
        },
      },
    },

  // The compose fragment every service reading those secrets needs. A provider has no
  // health of its own, so `started` is the only condition it can satisfy.
  secretsReady:: { [collections.role.SECRETS]: { condition: collections.condition.started } },
}
