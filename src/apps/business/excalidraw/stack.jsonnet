// Compiles to compose.yaml and stack.services.yaml — do not edit the YAML.
// No secrets — no env_file needed.
local lib = import 'lib.libsonnet';
local reg = lib.registry;
local role = reg.role;

local name = 'excalidraw';
local room = 'room';         // the collaboration websocket server — app-specific, no shared role

local appVersion = 'latest';
local roomVersion = 'latest';
local appPort = 80;
local roomPort = 80;

// Public URL of the collaboration (websocket) server. The excalidraw web UI bakes this
// into its assets at boot (the sed below), so the browser dials it directly — it must be
// publicly reachable via the edge, pointed at the published roomPort (18019).
local wsServerUrl = 'https://draw-room.' + reg.domains.ktbcloud;

lib.render(
  name,
  lib.Stack(name, function(ref) {
    // ── App: the excalidraw drawing web UI ─────────────────────────────────────
    [role.APP]: lib.Service {
      image: 'excalidraw/excalidraw:' + appVersion,
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
      expose: [std.toString(appPort)],
      ports: ['%s:18018:%s' % [reg.ips.loopback, appPort]],
    },

    // ── Room: the collaboration websocket server ───────────────────────────────
    [room]: lib.Service {
      image: 'excalidraw/excalidraw-room:' + roomVersion,
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
      expose: [std.toString(roomPort)],
      ports: ['%s:18019:%s' % [reg.ips.loopback, roomPort]],
    },
  }),
)
