# excalidraw-full

[excalidraw-full](https://github.com/BetterAndBetterII/excalidraw-full) — the Excalidraw
editor, realtime collaboration, and scene persistence in a single Go binary. Unlike the
sibling `excalidraw` stack (separate client + room server, no persistence), scenes are
saved to disk here, so drawings survive restarts.

Source of truth: `compose.jsonnet` — don't edit the generated YAML.

## Shape

- One container, one port (`3002`), published on `127.0.0.1:18020`.
- `STORAGE_TYPE=filesystem` → scenes persist to the `excalidraw-full_app` volume at `/root/data`.
- No secrets. Auth (GitHub OAuth / JWT) is left unconfigured on purpose: the editor,
  `/socket.io` collab, and the anonymous save/share-link endpoints all work without it.
  Access is gated at the edge, not by the app.

## Deploy

Deployed via Komodo (`server = littlebuddy`). No Infisical bundle.

Public exposure is a Pangolin route pointed at the host's `18020` — add it in Pangolin
(no in-repo edge config for this stack).

## Caveats

- The Firestore-compat room-backup path that stock Excalidraw's client also calls is
  in-memory only, not written to the volume. A container restart can drop a room's
  last-known scene for anyone who didn't use the explicit save/share-link flow.
- `latest` tag — pin a digest/tag if you want reproducible deploys.
