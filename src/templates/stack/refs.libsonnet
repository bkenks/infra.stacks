// Every name this stack owns, in one place. stack.jsonnet imports this file, so the
// manifest and the compose document can never disagree — and a name is written once even
// when it is read from four services.
//
// Nothing here is a compose document; it is a table of strings.
local lib = import 'lib.libsonnet';

lib.Project {
  // The one string a stack has to choose. Containers become <name>_<role>, volumes
  // <name>_<key>, and it is the name the private bridge is given in stack.jsonnet.
  name:: 'example',  // ← rename me

  // The env files compose interpolates into services.yaml. Register the bundle in
  // devlib/registry.libsonnet and pass the KEY, so the agent and this stack derive the same
  // path: `lib.Secret('example')`. Until it is registered, spell it out. A stack with no
  // secrets drops this field entirely.
  envFiles:: [lib.collections.dirs.secrets + '/example.env'],

  // Services, keyed by the role they play. Roles come from lib.collections.role rather than bare
  // strings, so `db` is never also `database` in another stack. A service whose name is
  // genuinely app-specific (guacd, gerbil) is a plain local instead.
  app:: self.Service { role:: lib.collections.role.APP },
  db:: self.Service { role:: lib.collections.role.DB },

  // Volumes this stack owns. The key is the compose-local handle; `name` is what it is
  // called on the host.
  appData:: self.Volume { key:: 'app' },
  dbData:: self.Volume { key:: 'db' },
}
