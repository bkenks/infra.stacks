#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["PyYAML>=6"]
# ///
"""Render a .jsonnet entrypoint to the files its top-level keys name; print each path.

An entrypoint evaluates to {'<filename>': <content>} and writes only into its own
directory, so each directory holds exactly one .jsonnet standing next to the files it
generates. Dict content is dumped as YAML; string content is written verbatim, since the
Infisical fragments carry Go-template bytes that must not be reparsed.

Every output gets the GENERATED header, which doubles as an ownership claim: it names the
entrypoint that produced the file. A stale file is deleted only if it claims this
entrypoint, or claims one that no longer exists here -- so hand-written YAML (no header)
and a live sibling's output are both left alone.

Imports resolve by bare name via the -J jpath, so a source at any depth does
`import 'registry.libsonnet'`. uv resolves PyYAML from the metadata above; the only
ambient requirement is `jsonnet` on PATH.
"""

import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

import yaml

HEADER = "# GENERATED from {src} by .jsonnet/render.py — DO NOT EDIT.\n"
CLAIM = re.compile(r"^# GENERATED from (\S+) by ")
SWEEPABLE = ("*.yaml", "*.yml")


def die(msg: str) -> "None":
    print(f"render.py: {msg}", file=sys.stderr)
    raise SystemExit(1)


def run_jsonnet(src: Path, lib: Path) -> "dict":
    # stderr inherits, so jsonnet's own message keeps its line numbers. The non-zero exit
    # propagates: that is what makes lefthook's `set -e` abort the commit.
    proc = subprocess.run(
        ["jsonnet", "-J", str(lib), str(src)], stdout=subprocess.PIPE, text=True
    )
    if proc.returncode != 0:
        raise SystemExit(proc.returncode)
    doc = json.loads(proc.stdout)
    if not isinstance(doc, dict) or not doc:
        die(f"{src}: must evaluate to a non-empty object keyed by output filename")

    # TRANSITIONAL: an unconverted entrypoint still evaluates to a compose document, whose
    # top-level keys (name, services, volumes) never end in .yaml. Map it onto the new
    # contract via the old name-derived output. Delete this branch once every entrypoint
    # is converted.
    if not all(k.endswith((".yaml", ".yml")) for k in doc):
        return {f"{src.name[: -len('.jsonnet')]}.yaml": doc}
    return doc


def resolve(src: Path, key: str) -> Path:
    # An entrypoint renders into its own directory and nowhere else, so a key naming a
    # path rather than a file is a bug in the jsonnet, not a case to support.
    if key != Path(key).name or key in (".", ".."):
        die(f"{src}: output key must be a bare filename, got {key!r}")
    return src.parent / key


def claimed_by(path: Path) -> "str | None":
    # The entrypoint filename this file's header claims as its source, or None when the
    # file carries no header and is therefore hand-written.
    match = CLAIM.match(path.read_text(errors="ignore").partition("\n")[0])
    return match.group(1) if match else None


def write_atomic(path: Path, body: str) -> "None":
    # Write beside the target, then rename onto it: same directory means same filesystem
    # means rename(2), which is atomic. A failed write never truncates the live file.
    # mkstemp creates 0600, hence the chmod.
    fd, tmp_name = tempfile.mkstemp(dir=str(path.parent), prefix=f"{path.name}.")
    tmp = Path(tmp_name)
    try:
        with open(fd, "w") as fh:
            fh.write(body)
        os.chmod(tmp, 0o644)
        tmp.replace(path)
    except BaseException:
        tmp.unlink(missing_ok=True)
        raise


def main() -> "None":
    if len(sys.argv) != 2:
        die("usage: render.py path/to/<entrypoint>.jsonnet")
    src = Path(sys.argv[1])
    if not src.is_file():
        die(f"no such file: {src}")

    doc = run_jsonnet(src, Path(__file__).resolve().parent / "lib")
    header = HEADER.format(src=src.name)

    # Serialized up front, so a YAML failure on the last key cannot leave the directory
    # half-updated.
    rendered = {
        resolve(src, key): header
        + (content if isinstance(content, str) else yaml.safe_dump(content, width=4096))
        for key, content in doc.items()
    }

    for path, body in sorted(rendered.items()):
        write_atomic(path, body)

    # An entrypoint's outputs can no longer be inferred from its name, so a stale file is
    # found by the source its header claims. Only this directory is swept, because only
    # this directory is written into. A file owned by a sibling entrypoint that still
    # exists is left alone -- mid-migration a stack dir holds both compose.jsonnet and
    # compose.stack.jsonnet, and they must not delete each other's output. A file owned by
    # a source since renamed or removed is collected by whoever now owns the directory.
    orphans = []
    for pattern in SWEEPABLE:
        for stale in sorted(src.parent.glob(pattern)):
            if stale in rendered:
                continue
            owner = claimed_by(stale)
            if owner is None:
                continue  # hand-written; never ours to delete
            if owner == src.name or not (src.parent / owner).is_file():
                orphans.append(stale)
    for stale in orphans:
        stale.unlink()

    # lefthook consumes these; `git add -A --` stages a write or a deletion alike.
    for path in [*sorted(rendered), *orphans]:
        print(path)


if __name__ == "__main__":
    main()
