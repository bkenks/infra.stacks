local c = import 'compose.libsonnet';
local r = import 'registry.libsonnet';

{
    'newt.env': c.toEnv({
        PANGOLIN_ENDPOINT: 'https://pangolin.' + r.domains.ktbcloud,
    }),
}
