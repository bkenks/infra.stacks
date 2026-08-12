// The Service base and the Stack assembler.
//
// A stack file declares only what is genuinely unique about a service — image, ports, env.
// Identity is not one of those things: `Service` writes container_name, network alias and
// volume mounts in terms of `self.stack` and `self.role`, which do not exist yet at that
// point. Stack() merges them in afterwards and Jsonnet's late binding resolves every
// derived name at that moment, so the stack name is never threaded through as an argument.
//
// Every field the base sets is a plain field, so overriding one is just writing it again.
// That is the escape hatch for the handful of names other systems already depend on —
// postgres-db, komodo_core, pangolin's unprefixed containers.

// The convention, in one place: <stack>_<part>. Service keys stay bare roles, so a
// stack reads as `app`/`db` while everything it owns on the host carries the prefix.
local qualify(stack, part) = stack + '_' + part;

{
  // Mix into every service: `lib.Service { image: '...' }` is sugar for `lib.Service + {...}`.
  Service:: {
    // `self` binds to the nearest enclosing object, which inside the nested `networks`
    // literal below is the alias block, not the service. This names the service itself.
    local service = self,

    // Bound by Stack(). Left as errors so a Service built outside a stack fails with this
    // message instead of `field does not exist: stack` from somewhere further down.
    stack:: error 'lib.Service used outside lib.Stack(): no stack bound',
    role:: error 'lib.Service used outside lib.Stack(): no role bound',

    // Inputs. A trailing underscore marks a field you write that is not itself output.
    //
    // volumes_ is { key: '/container/path' } for volumes this stack owns. The key is the
    // compose-local handle; the real volume is registered by Stack() as <stack>_<key>, so
    // the name on the host carries the prefix while the mount here stays short.
    volumes_:: {},
    // Bind mounts and anything else Docker resolves itself — host paths, ./files/… — pass
    // through verbatim, because there is no name for the library to derive.
    mounts_:: [],

    // Extra networks this service joins on top of the stack's private bridge. Keyed by the
    // network name, valued as its *top-level* definition — the same shape volumes_ has, and
    // for the same reason: the membership is written on the service that needs it and Stack()
    // hoists the definition, so the two halves cannot drift. Build entries with
    // lib.network.attach (someone else owns it) or lib.network.create (this stack owns it).
    networks_:: {},

    // network_mode: service:x means this container has no network stack of its own, so a
    // networks_ entry could never take effect. Say so here rather than at `docker compose up`.
    assert !std.objectHas(service, 'network_mode') || std.length(service.networks_) == 0 :
      'lib.Service(%s): network_mode shares another container\'s netns, so it cannot join networks_'
      % service.container_name,

    container_name: qualify(self.stack, self.role),
    restart: 'unless-stopped',

    // The alias is what other services in the stack dial. It matches container_name by
    // default; komodo overrides it because Komodo's own config already says komodo_core.
    //
    // A service sharing another's netns (network_mode: service:x) has no network stack of
    // its own, and Compose rejects the whole project — not just the service — if both keys
    // are present. prune drops the null.
    // Every networks_ entry carries the same alias. It is redundant with Docker resolving
    // container_name on every network the container joins, but std.prune below deletes empty
    // objects recursively, and a bare `{ <net>: {} }` would lose the membership with it.
    networks: if std.objectHas(service, 'network_mode')
              then null
              else { default: { aliases: [service.container_name] } }
                   + { [net]: { aliases: [service.container_name] } for net in std.objectFields(service.networks_) },

    volumes: [
      '%s:%s' % [key, self.volumes_[key]]
      for key in std.objectFields(self.volumes_)
    ] + self.mounts_,
  },

  // services is `function(ref) { <role>: Service {...} }`. Returns the stack.services.yaml
  // body. The function is called twice, which is what makes cross-service references
  // checkable — see the two-phase note below.
  //
  // networks is merged over the top-level block, so it is how a stack that needs the private
  // bridge to be something else (pangolin's ipv6) redefines `default` — but it never removes
  // it: the bridge every service implicitly attaches to is always emitted. Additional networks
  // are not declared here — a service names its own in networks_ and they are hoisted.
  Stack(name, services, networks=null)::
    assert std.isFunction(services) :
      'lib.Stack(%s): services must be `function(ref) {...}`, not a bare object' % name;

    // Phase one asks the function only for its keys. Listing an object's fields never
    // forces their values, so the service bodies — which dereference `ref` — are untouched
    // here, and passing null for a `ref` they have not received yet is not a cycle.
    local roles = std.objectFields(services(null));

    // The reference table, phase two's argument. Every service this stack declares, keyed
    // by role, valued as the name it will actually carry on the host. Reaching for a role
    // the stack does not declare is `field does not exist` at evaluation time — caught by
    // the editor and by lefthook, rather than by a container that never starts.
    local ref = { [role]: qualify(name, role) for role in roles };

    local built = services(ref);
    local bound = { [role]: built[role] + { stack:: name, role:: role } for role in roles };

    // Top-level volume registration is derived from the services that mount them, so a
    // volume is declared once, where it is used, and cannot drift out of sync here. Two
    // services mounting the same key (openproject's assets) collapse to one entry.
    // std.set dedupes: a volume mounted by several services (authentik's data, openproject's
    // assets) is one entry here, and an object comprehension would reject the repeat.
    local volumeKeys = std.set(std.flattenArrays([
      std.objectFields(bound[role].volumes_)
      for role in roles
    ]));
    local volumes = { [key]: { name: qualify(name, key) } for key in volumeKeys };

    {
      name: name,

      // prune drops the empty `volumes: []` from services that mount nothing, rather than
      // emitting a dead key in every service block.
      services: { [role]: std.prune(bound[role]) for role in roles },

      // `default` is Compose's reserved key, not a name — it is what attaches the network
      // to every service implicitly, and every Service's alias block names it, so it is
      // emitted unconditionally. The stack's name lands on `name:` underneath it.
      //
      // Order is the whole contract: hoisted networks, then the private bridge, then the
      // argument. A stack that passes only a shared network keeps its bridge; one that
      // passes `default` (pangolin's ipv6) redefines it, because it is merged last.
      networks: { default: { name: name } }
                + (if networks != null then networks else {}),
    } + (if std.length(volumes) > 0 then { volumes: volumes } else {}),
}
