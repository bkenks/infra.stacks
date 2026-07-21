// Compiles to compose.yaml and compose.stack.yaml — do not edit the YAML.
// No secrets — no env_file needed.
local c = import 'compose.libsonnet';
local reg = import 'registry.libsonnet';

local stack = 'excalidraw';
local s = c.stack(stack);
local n = s.names;
local app = reg.roles.app;   // 'app' — the drawing web UI
local room = 'room';         // the collaboration websocket server

local appVersion = 'latest';
local roomVersion = 'latest';
local appPort = 80;
local roomPort = 80;

// Public URL of the collaboration (websocket) server. The excalidraw web UI bakes this
// into its assets at boot (the sed below), so the browser dials it directly — it must be
// publicly reachable via the edge, pointed at the published roomPort (18019).
local wsServerUrl = 'https://draw-room.' + reg.domains.ktbcloud;

local manifest = {
  name: stack,

  services: {
    // ── App: the excalidraw drawing web UI ─────────────────────────────────────
    [app]: {
      image: 'excalidraw/excalidraw:' + appVersion,
      container_name: n.container(app),
      // Rewrite the hard-coded public collab host in the built assets to ours, then
      // start nginx. Runs on every boot so an image update can't drift the URL.
      entrypoint: '/bin/sh',
      command: [
        '-c',
        // `$$` is compose escaping → a literal `$` reaches the container shell, which
        // expands VITE_APP_WS_SERVER_URL from the service environment (a single `$`
        // would be interpolated away by compose at parse time).
        |||
          echo "Replacing WebSocket URL with: $$VITE_APP_WS_SERVER_URL"
          find /usr/share/nginx/html/assets -type f -name "*.js" -exec sed -i 's|https://oss-collab\.excalidraw\.com|'$$VITE_APP_WS_SERVER_URL'|g' {} +
          echo "Starting nginx..."
          nginx -g 'daemon off;'
        |||,
      ],
      stdin_open: true,
      environment: {
        NODE_ENV: 'production',
        VITE_APP_WS_SERVER_URL: wsServerUrl,
      },
      restart: 'unless-stopped',
      healthcheck: {
        test: ['CMD-SHELL', 'wget -qO- http://127.0.0.1:' + std.toString(appPort) + '/ >/dev/null 2>&1 || exit 1'],
        interval: '30s',
        timeout: '5s',
        retries: 3,
        start_period: '20s',
      },
      security_opt: ['no-new-privileges:true'],
      cap_drop: ['ALL'],
      cap_add: ['CHOWN', 'SETGID', 'SETUID'],
      tmpfs: [
        '/tmp:rw,noexec,nosuid,size=64m',
        '/var/cache/nginx/client_temp:rw,noexec,nosuid,size=64m',
      ],
      networks: {
        default: { aliases: [n.container(app)] },
      },
      expose: [std.toString(appPort)],
    } + c.publish(18018, appPort),

    // ── Room: the collaboration websocket server ───────────────────────────────
    [room]: {
      image: 'excalidraw/excalidraw-room:' + roomVersion,
      container_name: n.container(room),
      restart: 'unless-stopped',
      read_only: true,
      tmpfs: ['/tmp:rw,noexec,nosuid,size=64m'],
      security_opt: ['no-new-privileges:true'],
      cap_drop: ['ALL'],
      healthcheck: {
        test: ['CMD-SHELL', 'wget -qO- http://127.0.0.1:' + std.toString(roomPort) + '/ >/dev/null 2>&1 || exit 1'],
        interval: '30s',
        timeout: '5s',
        retries: 3,
        start_period: '20s',
      },
      networks: {
        default: { aliases: [n.container(room)] },
      },
      expose: [std.toString(roomPort)],
    } + c.publish(18019, roomPort),
  },

  networks:
    s.network.default,
};

c.render(stack, manifest)
