# Garage Admin API — Bruno collection

Generated from the official OpenAPI spec (`garage-admin-v2.json`, Garage admin API **v2.3.0**,
49 operations). Every request was replayed against `snaszy` to confirm the route resolves and
the body shape is accepted.

## Setup

1. Open the collection in Bruno, select the **snaszy** environment.
2. Set the `adminToken` secret var to `admin_token` from the NAS's `garage.toml`.

The environment ships with:

| Var | Value |
|---|---|
| `baseUrl` | `http://100.91.182.94:18903` (admin API) |
| `s3Endpoint` | `http://100.91.182.94:18900` (S3 API) |
| `region` | `garage` |
| `adminToken` | secret — set it yourself |

Reachable over Tailscale only. `100.91.182.94` is `snaszy`.

## Layout

One folder per spec tag: Access key, Admin API token, Block, Bucket, Bucket alias,
Cluster, Cluster layout, Node, Permission, Special endpoints, Worker.

`Special endpoints` (`/health`, `/metrics`, `/check`) need no token; everything under
`/v2/` uses bearer auth.

## Creating a backup bucket for zerobyte

1. `Bucket/CreateBucket` — set `globalAlias` to `zerobyte`
2. `Access key/CreateKey` — set `name`, save the returned key ID **and secret**
3. `Permission/AllowBucketKey` — pass the bucket ID and access key ID from the two
   responses above, with `read` and `write` set to `true`

Optional-struct fields are pre-filled as `null` so requests post cleanly as-is; fill in
only what you need.

## Regenerating

The spec is pinned here as `garage-admin-v2.json`. To refresh:
<https://garagehq.deuxfleurs.fr/api/garage-admin-v2.json>
