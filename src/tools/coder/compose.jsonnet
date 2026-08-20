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

// ——————————————————————————————————————————

{
  services: {
    [ app.key ]: {
      image: "ghcr.io/coder/coder:" + coderVersion,
      ports: [
        col.ip.loopback + ":7080:7080"
      ],
      environment: {
        CODER_PG_CONNECTION_URL: "postgresql://${POSTGRES_USER:-username}:${POSTGRES_PASSWORD:-password}@database/${POSTGRES_DB:-coder}?sslmode=disable",
        CODER_HTTP_ADDRESS: "0.0.0.0:7080",
        CODER_ACCESS_URL: "coder." + col.domain.ktbinternal,
      },
      volumes: ["/var/run/docker.sock:/var/run/docker.sock", app.volumeHome.key + ":" + app.volumeHome.mount],
      depends_on: {
        database: {
          condition: "service_healthy" 
        }
      }
    },

    [ db.key ]: {
      image: "postgres:17",
      environment:{
        POSTGRES_USER: "${POSTGRES_USER}",
        POSTGRES_PASSWORD: "${POSTGRES_PASSWORD}",
        POSTGRES_DB: "${POSTGRES_DB}",
      },
      volumes: [ db.volData.key + ":" + db.volData.mount ],
      healthcheck:{
        test: [
          "CMD-SHELL",
          "pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}",
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