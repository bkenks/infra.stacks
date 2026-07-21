#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["PyYAML>=6"]
# ///
#MISE description="Rebuild the .deploy/ tree from src/"
"""Build src/ into .deploy/ — the tree Komodo actually deploys from.

.deploy mirrors the *contents* of src/, path-for-path. Every non-jsonnet file is copied to
the same relative path, then each .jsonnet entrypoint renders its outputs alongside its
own mirrored directory. So `src/platform/edge/dnsmasq/files/hosts.jsonnet` produces
`.deploy/platform/edge/dnsmasq/files/hosts`, and every `./files/...` bind mount in the
generated compose keeps working unchanged.

src/ holds stacks and nothing else. Repo infrastructure (.mise/, .jsonnet/, komodo/,
lefthook.yml, docs) lives outside it and is never copied, so this script needs no
ignore list.

The build is destructive and total: .deploy is removed and rebuilt from scratch, so a
deleted stack or a renamed output leaves nothing behind. That is the whole reason for the
separate tree — generated files never share a directory with hand-written ones, so there
is no ownership question and no stale-file sweep.

An entrypoint evaluates to {'<filename>': <content>} and may only name bare filenames.
Dict content is dumped as YAML; string content is written verbatim, since the Infisical
fragments carry Go-template bytes that must not be reparsed.

Imports resolve by bare name via the -J jpath, so a source at any depth does
`import 'registry.libsonnet'`. uv resolves PyYAML from the metadata above; the `jsonnet`
binary and uv itself are pinned in mise.toml.

This file lives in .mise/tasks/, so mise discovers it as the `render` task (extension stripped) with no
declaration in mise.toml — `mise run render` and `./.mise/tasks/render.py` are the same thing.
"""

import json
import shutil
import subprocess
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "src"
LIB = ROOT / ".jsonnet" / "lib"
DEPLOY = ROOT / ".deploy"
HEADER = "# GENERATED from {src} by .mise/tasks/render.py — DO NOT EDIT.\n"

# src/ holds stacks and nothing else, so there is no repo infrastructure to filter out:
# everything in there is either an entrypoint or an asset. A .libsonnet is neither — it
# lives in .jsonnet/lib and is only ever imported.
SKIP_NAMES = {".DS_Store"}
SKIP_SUFFIXES = {".libsonnet"}


def die(msg: str) -> "None":
    print(f"render.py: {msg}", file=sys.stderr)
    raise SystemExit(1)


def sources() -> "list[Path]":
    # Every file under src/, as paths relative to src/ — .deploy mirrors src/'s contents,
    # not src/ itself, so src/apps/x lands at .deploy/apps/x.
    return sorted(
        p.relative_to(SRC)
        for p in SRC.rglob("*")
        if p.is_file() and p.name not in SKIP_NAMES and p.suffix not in SKIP_SUFFIXES
    )


def run_jsonnet(src: Path) -> "dict":
    # stderr inherits, so jsonnet's own message keeps its line numbers. The non-zero exit
    # propagates: that is what makes lefthook's `set -e` abort the commit.
    proc = subprocess.run(
        ["jsonnet", "-J", str(LIB), str(SRC / src)], stdout=subprocess.PIPE, text=True
    )
    if proc.returncode != 0:
        raise SystemExit(proc.returncode)
    doc = json.loads(proc.stdout)
    if not isinstance(doc, dict) or not doc:
        die(f"{src}: must evaluate to a non-empty object keyed by output filename")
    return doc


def body(src: Path, key: str, content: "dict | str") -> str:
    # An entrypoint renders into its own directory and nowhere else, so a key naming a
    # path rather than a file is a bug in the jsonnet, not a case to support.
    if key != Path(key).name or key in (".", ".."):
        die(f"{src}: output key must be a bare filename, got {key!r}")
    if isinstance(content, str):
        return HEADER.format(src=src.name) + content
    return HEADER.format(src=src.name) + yaml.safe_dump(content, width=4096)


def main() -> "None":
    if len(sys.argv) != 1:
        die("usage: render.py  (builds the whole repo into .deploy/)")

    entrypoints = []
    assets = []
    for rel in sources():
        (entrypoints if rel.suffix == ".jsonnet" else assets).append(rel)
    if not entrypoints:
        die(f"no .jsonnet entrypoints under {SRC}")

    # Rendered up front, so a jsonnet or YAML failure cannot leave a half-built tree
    # standing where the previous good one used to be.
    rendered = {
        DEPLOY / rel.parent / key: body(rel, key, content)
        for rel in entrypoints
        for key, content in run_jsonnet(rel).items()
    }

    shutil.rmtree(DEPLOY, ignore_errors=True)
    for rel in assets:
        dest = DEPLOY / rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(SRC / rel, dest)
    for path, text in sorted(rendered.items()):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)

    print(f"render.py: {len(entrypoints)} entrypoints, {len(rendered)} rendered, "
          f"{len(assets)} copied → {DEPLOY.relative_to(ROOT)}/")


if __name__ == "__main__":
    main()
