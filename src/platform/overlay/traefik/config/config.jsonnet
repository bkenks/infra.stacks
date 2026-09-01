local ref = import "../ref.libsonnet";

{
  [ref.config.traefik.name]: {
    entryPoints: {
      web: {
        address: ':1111',
      },
    },
    providers: {
      docker: {
        exposedByDefault: false,
      },
    },
    log: {
      level: 'INFO',
    },
    accessLog: {},
  }
}