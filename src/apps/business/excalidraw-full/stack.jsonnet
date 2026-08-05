// Compiles to compose.yaml and stack.services.yaml — do not edit the YAML.
// No secrets — no env_file needed.
//
// excalidraw-full (BetterAndBetterII) — the Excalidraw editor, realtime collaboration,
// and scene persistence all in one Go binary on a single port (3002). Unlike the sibling
// `excalidraw` stack (client + separate room server, no persistence), this one saves
// scenes to disk, so drawings survive restarts.
//
// Auth is left unconfigured on purpose: with the GitHub-OAuth / JWT vars unset the server
// still boots and serves the editor, `/socket.io` collab, and the anonymous save/share-link
// endpoints (`/api/v2/post`, `/api/v2/{id}`) — which is what persists to the volume below.
// Only the JWT-gated personal-canvas dashboard and AI passthrough are disabled. Access is
// controlled at the edge, not by the app.
local lib = import 'lib.libsonnet';
local reg = lib.registry;
local role = reg.role;

local name = 'excalidraw-full';
local version = 'latest';
local port = 3002;

lib.render(
  name,
  lib.Stack(name, function(ref) {
    [role.APP]: lib.Service {
      image: 'ghcr.io/betterandbetterii/excalidraw-full:' + version,
      environment: {
        // Durable scene storage on disk (vs the default in-memory store).
        STORAGE_TYPE: 'filesystem',
        LOCAL_STORAGE_PATH: '/root/data',
        // EXCALIDRAW_BACKEND_HOST intentionally unset: the app falls back to the incoming
        // request Host, which behind the edge is the correct public domain.
      },
      volumes_:: { app: '/root/data' },
      security_opt: ['no-new-privileges:true'],
      cap_drop: ['ALL'],
      expose: [std.toString(port)],
      ports: ['%s:18020:%s' % [reg.ips.loopback, port]],
    },
  }),
)
