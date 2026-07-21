#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["PyYAML>=6"]
# ///
"""Build the whole repo into .deploy/ — the tree Komodo actually deploys from.

.deploy mirrors the source tree path-for-path. Every non-jsonnet file is copied to the
same relative path, then each .jsonnet entrypoint renders its outputs alongside its own
mirrored directory. So `platform/edge/dnsmasq/files/hosts.jsonnet` produces
`.deploy/platform/edge/dnsmasq/files/hosts`, and every `./files/...` bind mount in the
generated compose keeps working unchanged.

The build is destructive and total: .deploy is removed and rebuilt from scratch, so a
deleted stack or a renamed output leaves nothing behind. That is the whole reason for the
separate tree — generated files never share a directory with hand-written ones, so there
is no ownership question and no stale-file sweep.

An entrypoint evaluates to {'<filename>': <content>} and may only name bare filenames.
Dict content is dumped as YAML; string content is written verbatim, since the Infisical
fragments carry Go-template bytes that must not be reparsed.

Imports resolve by bare name via the -J jpath, so a source at any depth does
`import 'registry.libsonnet'`. uv resolves PyYAML from the metadata above; the only
ambient requirement is `jsonnet` on PATH.
"""

import json
import shutil
import subprocess
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
LIB = ROOT / ".jsonnet" / "lib"
DEPLOY = ROOT / ".deploy"
HEADER = "# GENERATED from {src} by .jsonnet/render.py — DO NOT EDIT.\n"

# Repo infrastructure: versioned here, but not part of what gets deployed. .jsonnet/ is
# NOT pruned — its templates/ holds a real compiling stack, and rendering it on every
# build is what keeps the authoring template from silently rotting.
PRUNE_DIRS = {
    ".git", ".claude", ".config", ".deploy", ".github", ".scripts", ".vscode", "__pycache__",
}
SKIP_NAMES = {".DS_Store", "CLAUDE.md", "README.md", "lefthook.yml", ".gitignore", "render.py"}
# A .libsonnet is neither an entrypoint nor an asset — it is only ever imported.
SKIP_SUFFIXES = {".libsonnet"}


def die(msg: str) -> "None":
    print(f"render.py: {msg}", file=sys.stderr)
    raise SystemExit(1)


def sources() -> "list[Path]":
    # Everything under ROOT that survives the prune, as paths relative to ROOT.
    found = []
    stack = [ROOT]
    while stack:
        for entry in sorted(stack.pop().iterdir()):
            if entry.is_dir():
                if entry.name not in PRUNE_DIRS:
                    stack.append(entry)
            elif entry.name not in SKIP_NAMES and entry.suffix not in SKIP_SUFFIXES:
                found.append(entry.relative_to(ROOT))
    return sorted(found)


def run_jsonnet(src: Path) -> "dict":
    # stderr inherits, so jsonnet's own message keeps its line numbers. The non-zero exit
    # propagates: that is what makes lefthook's `set -e` abort the commit.
    proc = subprocess.run(
        ["jsonnet", "-J", str(LIB), str(ROOT / src)], stdout=subprocess.PIPE, text=True
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
        die("no .jsonnet entrypoints found — is this the repo root?")

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
        shutil.copy2(ROOT / rel, dest)
    for path, text in sorted(rendered.items()):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)

    print(f"render.py: {len(entrypoints)} entrypoints, {len(rendered)} rendered, "
          f"{len(assets)} copied → {DEPLOY.relative_to(ROOT)}/")


if __name__ == "__main__":
    main()
