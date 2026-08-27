local lib = import 'lib.libsonnet';
local col = lib.collections;
local reg = lib.registry;

local coderVersion = "latest";
local coderFQDN = "coder." + col.domain.ktbcloud;
local coderURL = "https://" + coderFQDN;

local secretsDepends = { secrets: { condition: "service_started" } };


// ——————————————————————————————————————————

local app = {
  key:: col.role.APP,
  volume:: {
    home:: { key:: "app-home", mount:: "/home/coder"}
  }, v:: self.volume,
};

local db = {
  key:: col.role.DB,
  volume:: {
    data:: { key:: "db-data", mount:: "/var/lib/postgresql/data"}
  }, v:: self.volume,
};

local n = {
  workspaces:: { local workspaces = self,
    key:: "workspaces",
    def:: {
      [workspaces.key]: {
        name: "coder-" + workspaces.key
      }
    }
  }
};

// ——————————————————————————————————————————



{
  compose: {
    networks:
      n.workspaces.def +
      { 
        default: {}
      },

    volumes: {
      [ app.v.home.key ]: {},
      [ db.v.data.key ]: {}
    },

    services: {
      secrets: {
        provider: {
          type: "infisical-secrets",
          options: {
            "credentials-file": reg.path.file.infisical_creds,
            domain: 'http://100.106.170.93:18043',
            "project-id": "2f0eb3d1-3e2a-4ce7-8060-5e47ad877e47",
            env: "prod",
            path: "/coder",
            recursive: true
          }
        }
      },

      [ app.key ]: {
        image: "ghcr.io/coder/coder:" + coderVersion,
        depends_on:
          secretsDepends +
          {
            [ db.key ]: {
              condition: "service_healthy" 
            }
          },
        volumes: [
          "/var/run/docker.sock:/var/run/docker.sock",
          app.v.home.key + ":" + app.v.home.mount
        ],
        networks: [
          "default",
          n.workspaces.key
        ],
        ports: [
          col.ip.loopback + ":7080:7080"
        ],
        environment: {
          // CODER_PG_CONNECTION_URL: via infisical-secrets
          CODER_HTTP_ADDRESS:             "0.0.0.0:7080",
          CODER_ACCESS_URL:               coderURL,
          CODER_AGENT_URL:                "http://coder-app-1:7080",
          // Traefik does not relay the custom `Upgrade: DERP` header; without this
          // the agent's tailnet relay never connects and every app 502s.
          CODER_DERP_FORCE_WEBSOCKETS:    "true",
          CODER_WILDCARD_ACCESS_URL:      "*." + coderFQDN,
        },
        user: "0:0"
      },

      [ db.key ]: {
        image: "postgres:17",
        depends_on: secretsDepends,
        // via infisical-secrets
        // environment:{
        //   POSTGRES_USER: "${POSTGRES_USER}",
        //   POSTGRES_PASSWORD: "${POSTGRES_PASSWORD}",
        //   POSTGRES_DB: "${POSTGRES_DB}",
        // },
        volumes: [ db.v.data.key + ":" + db.v.data.mount ],
        healthcheck:{
          test: [
            "CMD-SHELL",
            "pg_isready -U coder -d coder",
          ],
          interval: "5s",
          timeout: "5s",
          retries: "5",
        }
      }},
  },
}
