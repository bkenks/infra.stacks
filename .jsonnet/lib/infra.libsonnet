// infra.libsonnet
//
// Single import surface for every stack. With `jsonnet -J .jsonnet/lib` a stack
// at any depth imports this by bare name:
//
//   local infra = import 'infra.libsonnet';
//   local reg = infra.registry;
//   ... infra.net.join('proxy') ... infra.mixins.traefik(...) ...
{
  registry: import 'registry.libsonnet',
  net: import 'compose.libsonnet',
  mixins: import 'mixins.libsonnet',
}
