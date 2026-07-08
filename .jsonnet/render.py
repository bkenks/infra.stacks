#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["PyYAML>=6"]
# ///
"""Render a .jsonnet source to YAML next to it, and print the output path.

  Usage: .jsonnet/render.py path/to/<name>.jsonnet

Output naming:
  <name>.jsonnet   -> <name>.yaml         (single YAML doc). A stack splits its
                      source into compose.stack.jsonnet -> compose.stack.yaml
                      (the child) and compose.jsonnet -> compose.yaml (the Komodo
                      parent that `include`s the child + declares its env_files).
  services.jsonnet -> templates/          (MULTI-FILE: one agent-config fragment
                      per service; the object's string fields are written raw,
                      one file per field name. See services.jsonnet.)

Library imports resolve by bare name via the -J jpath below, so a source at any
depth does `import 'lib.libsonnet'`.

uv resolves PyYAML from the inline metadata above, so the only ambient
requirement is the `jsonnet` binary on PATH (go-jsonnet in this repo).
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
    # stderr always inherits so jsonnet's own diagnostics reach the terminal; a
    # non-zero exit aborts (lefthook's `set -e` relies on this to fail the commit).
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

    # Multi-file: services.jsonnet evaluates to { '<svc>.yaml': '<raw yaml fragment>' }.
    # `-S -m` writes each string field to templates/<svc>.yaml verbatim (the per-file
    # DO-NOT-EDIT header is baked into the fragment string). Render to a temp dir then
    # swap so a jsonnet error never leaves a half-written templates/.
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

    # Render to a temp file then swap into place — a jsonnet/YAML failure must never
    # truncate the real $out to a half-written file (same reasoning as the
    # services.jsonnet temp-dir swap). The temp lives in out_dir so the final
    # os.replace is an atomic same-filesystem rename.
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
