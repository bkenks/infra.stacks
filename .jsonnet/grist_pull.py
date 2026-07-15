#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Pull the registry data out of Grist into lib/registry.data.json.

Grist is the human-editing surface for the data that used to be hand-typed into
registry.libsonnet — hosts, domains, Infisical projects, and the secret catalogue. This
script fetches those tables over the Grist REST API and reshapes the flat records back
into the nested maps registry.libsonnet expects, keyed by each row's Name. The output is
committed, so `jsonnet`/render.py stay fully offline and every render is reproducible and
diffable in git; Grist only re-enters the loop when someone edits data and re-runs this.

Run before .jsonnet/render.py (locally or in CI):

    GRIST_URL=https://grist.ktbinternal.com \\
    GRIST_DOC_ID=<docId> \\
    GRIST_API_KEY=<key> \\
    .jsonnet/grist_pull.py

Reads the API key from GRIST_API_KEY (never stored here). No third-party deps — the API is
plain JSON over HTTPS, so urllib carries it.

Grist encoding notes this handles:
  - Choice List / Reference List cells arrive as ['L', v1, v2, ...]; the 'L' sentinel is
    stripped back to a plain list.
  - A Reference cell arrives as the target row's integer rowId; refs= resolves it to that
    row's Name so the JSON carries the key ('apps'), not an opaque id.
  - Empty cells ('', None, [], False) are dropped, so the output stays as sparse as the
    old hand-written registry (e.g. `edge` present only when true, optional fields omitted).
"""

import json
import os
import sys
import urllib.error
import urllib.request
from dataclasses import dataclass, field
from pathlib import Path

OUT = Path(__file__).resolve().parent / "lib" / "registry.data.json"


@dataclass
class Table:
    name: str  # Grist table id
    out: str  # key under which its data lands in registry.data.json
    shape: str  # 'record' → name:{fields}; 'flat' → name:value
    key: str = "Name"  # column whose value keys the output map
    value_col: str = ""  # (flat only) column holding the scalar value
    cols: dict = field(default_factory=dict)  # (record only) grist col → json field
    refs: dict = field(default_factory=dict)  # grist col → table name it references


# Column names here must match the Grist table headers exactly. To move another slice of
# registry.libsonnet into Grist later, add a Table entry and a matching `data.<out>`
# reference in registry.libsonnet — nothing else changes.
SPECS = [
    Table(
        "Hosts", out="hosts", shape="record",
        cols={
            "TailscaleIP": "ip",
            "LanIP": "lan",
            "PublicIP": "public",
            "DnsOverride": "dns",
            "Aka": "aka",
            "Edge": "edge",
        },
    ),
    Table("Domains", out="domains", shape="flat", value_col="Fqdn"),
    Table("InfisicalProjects", out="infisicalProjects", shape="flat", value_col="UUID"),
    Table(
        "Secrets", out="secrets", shape="record",
        cols={
            "Project": "project",
            "Folder": "folder",
            "Dest": "dest",
            "Type": "type",
            "Env": "env",
            "Key": "key",
            "Keys": "keys",
        },
        refs={"Project": "InfisicalProjects"},
    ),
]


def die(msg: str) -> "None":
    print(f"grist_pull.py: {msg}", file=sys.stderr)
    raise SystemExit(1)


def fetch(base: str, doc: str, table: str, key: str) -> "list[dict]":
    url = f"{base}/api/docs/{doc}/tables/{table}/records"
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {key}"})
    try:
        with urllib.request.urlopen(req) as resp:
            body = json.loads(resp.read())
    except urllib.error.HTTPError as e:
        die(f"{table}: {e.code} {e.reason} — check GRIST_DOC_ID, the table name, and the key's access")
    except urllib.error.URLError as e:
        die(f"{table}: cannot reach {base} ({e.reason})")
    return body["records"]


def unlist(v):
    # Grist tags list-valued cells (Choice List, Reference List) with a leading 'L'.
    return list(v[1:]) if isinstance(v, list) and v and v[0] == "L" else v


def empty(v) -> bool:
    # Sparse output: a blank cell should be absent, not a null/""/false in the JSON.
    return v is None or v == "" or v == [] or v is False


def build(spec: Table, records: "list[dict]", ref_maps: "dict[str, dict]") -> dict:
    out = {}
    for rec in records:
        f = rec["fields"]
        name = f.get(spec.key)
        if empty(name):
            continue  # a half-created row in the UI; no key, skip it

        if spec.shape == "flat":
            val = f.get(spec.value_col)
            if not empty(val):
                out[name] = val
            continue

        entry = {}
        for col, jkey in spec.cols.items():
            val = unlist(f.get(col))
            if col in spec.refs and isinstance(val, int):
                # Resolve a reference rowId → the target row's key (e.g. 3 → 'apps').
                val = ref_maps[spec.refs[col]].get(val, val)
            if jkey == "keys" and isinstance(val, str) and val:
                val = json.loads(val)  # map-type renames stored as a JSON blob
            if not empty(val):
                entry[jkey] = val
        out[name] = entry
    return out


def main() -> "None":
    base = os.environ.get("GRIST_URL", "").rstrip("/")
    doc = os.environ.get("GRIST_DOC_ID", "")
    api_key = os.environ.get("GRIST_API_KEY", "")
    missing = [n for n, v in [("GRIST_URL", base), ("GRIST_DOC_ID", doc), ("GRIST_API_KEY", api_key)] if not v]
    if missing:
        die(f"set {', '.join(missing)}")

    # rowId → Name for every referenced table, so build() can resolve Reference cells.
    raw = {s.name: fetch(base, doc, s.name, api_key) for s in SPECS}
    ref_maps = {
        s.name: {rec["id"]: rec["fields"].get(s.key) for rec in raw[s.name]}
        for s in SPECS
    }

    data = {s.out: build(s, raw[s.name], ref_maps) for s in SPECS}
    OUT.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
    print(OUT)


if __name__ == "__main__":
    main()
