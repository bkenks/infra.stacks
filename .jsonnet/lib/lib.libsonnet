// lib.libsonnet
//
// Single import surface for every stack. With `jsonnet -J .jsonnet/lib` a stack
// at any depth imports this by bare name:
//
//   local lib = import 'lib.libsonnet';
//   local reg = lib.registry;
//   ... lib.compose.join('proxy') ... lib.mixins.proxyAdd(...) ...
{
  registry: import 'registry.libsonnet',
  compose: import 'compose.libsonnet',
  mixins: import 'mixins.libsonnet',
}
