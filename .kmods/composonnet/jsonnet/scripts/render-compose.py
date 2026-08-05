#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["PyYAML>=6"]
# ///
#MISE description="Render every .jsonnet under a given dir into files beside it"
"""Render each .jsonnet entrypoint into output files sitting next to it.

An entrypoint evaluates to {'<filename>': <content>}. Outputs are named
`<entrypoint stem>.<key stem><key suffix>` — `stack.jsonnet` keyed `services.yaml`
yields `stack.services.yaml` — except for the compose names in VERBATIM_NAMES.

Overridable by env (RENDER_COMPOSE_ROOT, RENDER_COMPOSE_SRC, RENDER_COMPOSE_JPATH) and
by the `src` positional and `-J`/`--jpath` flag, which win over both. `mise run
render-compose` renders the whole tree; running the script directly renders the cwd.
"""

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path

import yaml

# Defaults hang off the cwd, so the script renders wherever it is called from. SRC and
# JPATH env entries resolve relative to ROOT; an absolute entry stays as given.
_DEFAULT_ROOT = Path.cwd().resolve()

ROOT = (
    Path(os.environ["RENDER_COMPOSE_ROOT"]).resolve()
    if os.environ.get("RENDER_COMPOSE_ROOT")
    else _DEFAULT_ROOT
)

SRC_DEFAULT = (
    (ROOT / os.environ["RENDER_COMPOSE_SRC"]).resolve()
    if os.environ.get("RENDER_COMPOSE_SRC")
    else ROOT
)

# The -J jpath, so a source at any depth does `import 'lib/lib.libsonnet'`.
JPATH = (
    [(ROOT / p).resolve() for p in os.environ["RENDER_COMPOSE_JPATH"].split(":") if p]
    if os.environ.get("RENDER_COMPOSE_JPATH")
    else [
        ROOT,
        ROOT / "lib",
        ROOT / ".lib",
        ROOT / "jsonnet" / "lib",
        ROOT / ".jsonnet" / "lib",
        ROOT / ".kmods" / "jsonnet" / "lib",
    ]
)

# The whole ownership model: this exact line, first in the file, is what marks a file as
# ours to delete and rewrite. Generated and hand-written files share a directory; a file
# without the header is hand-written and is never deleted or overwritten. Changing this
# orphans every file rendered by an older build, so it is matched by prefix and must
# stay stable.
MARKER = "# GENERATED from "
HEADER = MARKER + "{src} by render.py — DO NOT EDIT.\n"

SKIP_NAMES = {".DS_Store"}

# Compose's own discovery rules recognise these names and no others, so an output keyed
# with one keeps it verbatim instead of taking the entrypoint prefix. `docker compose` in
# the stack directory then finds the file with no -f flag, and Komodo's file_paths name it
# as-is. Two entrypoints in one directory both claiming a name here collide, which the
# already-rendered check in main() reports.
VERBATIM_NAMES = {
    "compose.yaml",
    "compose.yml",
    "docker-compose.yaml",
    "docker-compose.yml",
}


def die(msg: str) -> "None":
    print(f"render.py: {msg}", file=sys.stderr)
    raise SystemExit(1)


def entrypoints(src: Path) -> "list[Path]":
    # Relative to src/ so messages read as the paths a person would type. .libsonnet is
    # not an entrypoint — the library lives in lib/ and is only ever imported.
    return sorted(
        p.relative_to(src)
        for p in src.rglob("*.jsonnet")
        if p.is_file() and p.name not in SKIP_NAMES
    )


def generated(path: Path) -> bool:
    try:
        with path.open(encoding="utf-8") as fh:
            return fh.readline().startswith(MARKER)
    except (OSError, UnicodeDecodeError):
        return False


def outputs(src: Path) -> "list[Path]":
    return sorted(p for p in src.rglob("*") if p.is_file() and generated(p))


def run_jsonnet(src_root: Path, src: Path, jpaths: "list[Path]") -> "dict":
    # stderr inherits, so jsonnet's own message keeps its line numbers. The non-zero exit
    # propagates: that is what makes lefthook's `set -e` abort the commit.
    jpath_args = [arg for jpath in jpaths for arg in ("-J", str(jpath))]
    proc = subprocess.run(
        ["jsonnet", *jpath_args, str(src_root / src)], stdout=subprocess.PIPE, text=True
    )
    if proc.returncode != 0:
        raise SystemExit(proc.returncode)
    doc = json.loads(proc.stdout)
    if not isinstance(doc, dict) or not doc:
        die(f"{src}: must evaluate to a non-empty object keyed by output filename")
    return doc


def dest(src_root: Path, src: Path, key: str) -> Path:
    # An entrypoint renders into its own directory and nowhere else, so a key naming a
    # path rather than a file is a bug in the jsonnet, not a case to support.
    if key != Path(key).name or key in (".", ".."):
        die(f"{src}: output key must be a bare filename, got {key!r}")
    if key in VERBATIM_NAMES:
        return src_root / src.parent / key
    name = Path(key)
    return src_root / src.parent / f"{src.stem}.{name.stem}{name.suffix}"


def body(src: Path, content: "dict | str") -> str:
    # String content is written verbatim: the Infisical fragments carry Go-template bytes
    # that must not be reparsed.
    if isinstance(content, str):
        return HEADER.format(src=src.name) + content
    return HEADER.format(src=src.name) + yaml.safe_dump(content, width=4096)


def parse_args() -> "argparse.Namespace":
    parser = argparse.ArgumentParser(
        description="Render every .jsonnet under a directory into files beside it"
    )
    parser.add_argument(
        "src",
        type=Path,
        nargs="?",
        default=SRC_DEFAULT,
        help="directory to sweep for .jsonnet entrypoints (default: "
        f"{SRC_DEFAULT}, or $RENDER_COMPOSE_SRC)",
    )
    parser.add_argument(
        "-J",
        "--jpath",
        dest="jpath",
        action="append",
        type=Path,
        help="library search path, repeatable (default: "
        + ", ".join(map(str, JPATH))
        + ", or $RENDER_COMPOSE_JPATH)",
    )
    return parser.parse_args()


def main() -> "None":
    args = parse_args()
    jpaths = args.jpath or JPATH
    src_root = args.src.resolve()

    srcs = entrypoints(src_root)
    if not srcs:
        die(f"no .jsonnet entrypoints under {src_root}")

    # Rendered up front, so a jsonnet or YAML failure aborts before anything on disk has
    # been touched.
    rendered: "dict[Path, str]" = {}
    owner: "dict[Path, Path]" = {}
    for src in srcs:
        for key, content in run_jsonnet(src_root, src, jpaths).items():
            path = dest(src_root, src, key)
            if path in rendered:
                die(
                    f"{src}: {path.relative_to(src_root)} is already rendered by "
                    f"{owner[path]}"
                )
            rendered[path] = body(src, content)
            owner[path] = src

    stale = [p for p in outputs(src_root) if p not in rendered]
    clashes = [p for p in rendered if p.exists() and not generated(p)]
    if clashes:
        die(
            "would overwrite hand-written files (rename the output key or the file): "
            + ", ".join(str(p.relative_to(src_root)) for p in sorted(clashes))
        )

    for path in stale:
        path.unlink()
    for path, text in sorted(rendered.items()):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)

    # stdout is the list of paths this build owns, written and removed alike — that is
    # what .config/lefthook.yml pipes into `git add`, so a commit stages the generated
    # files and nothing else the author left unstaged on purpose. The summary goes to
    # stderr to keep that list machine-readable.
    # Relative to ROOT where possible so the list feeds `git add` unchanged; a src outside
    # ROOT has no such relative form and is printed absolute.
    for path in sorted(stale) + sorted(rendered):
        print(path.relative_to(ROOT) if path.is_relative_to(ROOT) else path)
    print(
        f"render.py: {len(srcs)} entrypoints, {len(rendered)} rendered, "
        f"{len(stale)} stale removed",
        file=sys.stderr,
    )


if __name__ == "__main__":
    main()
