local lib = import "lib.libsonnet";
local refs = import "./ref.libsonnet";

local roleProxy = lib.collections.role.PROXY;
local configTraefikPath = refs.config.traefik.path.relative;
local configTraefikName = refs.config.traefik.fullFileName;

local project = lib.Project { local thisProject = self,
  name:: "container-gw",

  proxy:: thisProject.Service { // local thisProxy = self,
    role:: roleProxy,
    image:: "traefik",
    version:: "3.7",
    volume:: {
      sock:: "/var/run/docker.sock:/var/run/docker.sock",
      configTraefik:: configTraefikPath + ":/etc/traefik/" + configTraefikName + ":ro"
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
          proxy.volume.sock,
          proxy.volume.configTraefik
        ],
        network_mode: "host"
      }
    }
  }
}