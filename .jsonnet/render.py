#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["PyYAML>=6"]
# ///
"""Render a .jsonnet source to YAML next to it, and print the output path.

services.jsonnet is MULTI-FILE: writes one fragment per object field to templates/ instead.
Imports resolve by bare name via the -J jpath below, so a source at any depth does
`import 'lib.libsonnet'`. uv resolves PyYAML from the inline metadata above; the only
ambient requirement is `jsonnet` on PATH.
"""

import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import yaml


def die(msg: str) -> "None":
    print(f"render.py: {msg}", file=sys.stderr)
    raise SystemExit(1)


def run_jsonnet(args: "list[str]", *, capture: bool) -> str:
    # stderr always inherits; non-zero exit aborts (lefthook's `set -e` relies on this to fail commits).
    stdout = subprocess.PIPE if capture else subprocess.DEVNULL
    proc = subprocess.run(["jsonnet", *args], stdout=stdout, text=True)
    if proc.returncode != 0:
        raise SystemExit(proc.returncode)
    return proc.stdout or ""


def main() -> "None":
    if len(sys.argv) != 2:
        die("usage: render.py path/to/<name>.jsonnet")

    src = Path(sys.argv[1])
    if not src.is_file():
        die(f"no such file: {src}")
    out_dir = src.parent
    lib = Path(__file__).resolve().parent / "lib"

    # services.jsonnet evaluates to {'<svc>.yaml': '<raw fragment>'}; -S -m writes each
    # field to templates/<svc>.yaml. Rendered to a temp dir then swapped so a failure
    # never leaves a half-written templates/.
    if src.name == "services.jsonnet":
        out = out_dir / "templates"
        with tempfile.TemporaryDirectory() as tmp:
            run_jsonnet(["-J", str(lib), "-S", "-m", tmp, str(src)], capture=False)
            out.mkdir(parents=True, exist_ok=True)
            for stale in out.glob("*.yaml"):
                stale.unlink()
            for frag in Path(tmp).glob("*.yaml"):
                shutil.move(str(frag), str(out / frag.name))
        print(out)
        return

    # Rendered to a temp file then swapped into place so a jsonnet/YAML failure never
    # truncates $out; temp lives in out_dir so the replace is an atomic rename.
    out = out_dir / f"{src.name[: -len('.jsonnet')]}.yaml"
    doc = json.loads(run_jsonnet(["-J", str(lib), str(src)], capture=True))
    header = f"# GENERATED from {src.name} by .jsonnet/render.py — DO NOT EDIT.\n"
    body = yaml.safe_dump(doc, sort_keys=False, default_flow_style=False, width=4096)

    fd, tmp_name = tempfile.mkstemp(dir=str(out_dir), prefix=f"{out.name}.")
    tmp_path = Path(tmp_name)
    try:
        with open(fd, "w") as fh:
            fh.write(header)
            fh.write(body)
        tmp_path.replace(out)
    except BaseException:
        tmp_path.unlink(missing_ok=True)
        raise
    print(out)


if __name__ == "__main__":
    main()
