local lib = import 'lib.libsonnet';
local col = lib.collections;

local coderVersion = "latest";

local app = {
  key:: col.role.APP,
  volumeHome:: { key:: "app-home", mount:: "/home/coder"}
};

local db = {
  key:: col.role.DB,
  volData:: { key:: "db-data", mount:: "/var/lib/postgresql/data"}
};

local secretsDepends = { secrets: { condition: "service_started" } };

// ——————————————————————————————————————————

{
  services: {
    secrets: {
      provider: {
        type: "infisical-secrets",
        options: {
          "credentials-file": "/dev/shm/secrets/credentials.env",
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
      ports: [
        col.ip.loopback + ":7080:7080"
      ],
      environment: {
        // CODER_PG_CONNECTION_URL: via infisical-secrets
        CODER_HTTP_ADDRESS: "0.0.0.0:7080",
        CODER_ACCESS_URL: "coder." + col.domain.ktbinternal,
      },
      volumes: ["/var/run/docker.sock:/var/run/docker.sock", app.volumeHome.key + ":" + app.volumeHome.mount],
      depends_on: secretsDepends {
        [ db.key ]: {
          condition: "service_healthy" 
        }
      }
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
      volumes: [ db.volData.key + ":" + db.volData.mount ],
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

  volumes: {
    [ app.volumeHome.key ]: {},
    [ db.volData.key ]: {}
  }
}