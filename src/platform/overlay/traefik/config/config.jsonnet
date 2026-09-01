{
  traefik: {
    entryPoints: {
      web: {
        address: ':80',
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