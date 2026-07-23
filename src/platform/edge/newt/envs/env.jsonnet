local lib = import 'lib/lib.libsonnet';
local reg = lib.registry;

{
  'newt.env': lib.toEnv({
    PANGOLIN_ENDPOINT: reg.endpoint.pangolin.public.url,
  }),
}
