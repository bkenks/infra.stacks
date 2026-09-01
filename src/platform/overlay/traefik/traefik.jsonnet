local lib = import "lib.libsonnet";

local roleProxy = lib.collections.role.PROXY;

local project = lib.Project { local thisProject = self,
  name:: "container-gw",

  proxy:: thisProject.Service { // local thisProxy = self,
    role:: roleProxy,
    image:: "traefik",
    version:: "3.7",
    volume:: {
      sock:: "/var/run/docker.sock:/var/run/docker.sock"
    }
  }
};

{
  compose: {
    local proxy = project.proxy,

    services: {
      [proxy.key]: {
        image: proxy.image + ":v" + proxy.version,
        // Container Configuration —————————————————————
        container_name: proxy.ext,
        volumes: [
          project.proxy.volume.sock
        ],
        network_mode: "host"
      }
    }
  }
}