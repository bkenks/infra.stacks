local c = import 'compose.libsonnet';
local r = import 'registry.libsonnet';

{
    'newt.external.env': c.toEnv({
        PANGOLIN_ENDPOINT: 'https://pangolin.' + r.domains.ktbcloud,
    }),
    'newt.internal.env': c.toEnv({
        PANGOLIN_ENDPOINT: 'https://pangolin.' + r.domains.ktbinternal,
    }),
}