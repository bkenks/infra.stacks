#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# ///
# MISE description="Render every .jsonnet under src/ into the .yaml files it names"

"""Render each .jsonnet entrypoint into the .yaml files it names.

An entrypoint evaluates to an object whose top-level fields *are* the files it writes: each
field is a filename without its extension, each value the document to put there. A file that
writes one output names it like any other -- `{ services: {...} }` renders `services.yaml`
beside the entrypoint -- and a file that writes several just has several fields:

    { compose: {...}, services: {...} }   ->   compose.yaml, services.yaml

The entrypoint's own name has nothing to do with its output. What ties a generated file back
to its source is the header on line one, not the filename.

`*.libsonnet` is never an entrypoint, and a dot-prefixed directory (`.old/`, `.git/`) is
skipped entirely.

Ownership is that header. A file without it is hand-written: it is never deleted, and an
entrypoint that would overwrite one is a hard error. A generated file that the current build
no longer produces is removed, which is what makes a rebuild total -- a deleted stack, a
renamed entrypoint and a dropped field all leave nothing behind.

Everything renders before anything is written, so a jsonnet failure aborts with the tree
untouched.

Usage:
    render.py [SRC] [-J JPATH]...

SRC defaults to `src` under the repo root, JPATH to `devlib`; both resolve against the
repo root, which is this script's parent directory. stdout lists every path the build
owns, written and removed alike -- .config/lefthook.yml pipes it into `git add`. The
summary goes to stderr to keep that list machine-readable.

Requires the `jsonnet` binary on PATH (mise pins go-jsonnet).
"""

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

PROGRAM = "render.py"

# This exact prefix, first line of the file, is what marks a file as ours to delete and
# rewrite. Changing it orphans every file rendered by an older build, so it must stay
# stable.
MARKER = "# GENERATED from "

# A top-level field name has to survive becoming a filename: no slash to climb out of the
# stack's directory, no leading dot to hide from the stale sweep.
STEM = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]*")

REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_SRC = "src"
DEFAULT_JPATH = "devlib"


def die(message: str) -> None:
    """Print an error and exit non-zero."""
    print(f"{PROGRAM}: {message}", file=sys.stderr)
    sys.exit(1)


def parse_args() -> argparse.Namespace:
    """Parse the source directory and the jsonnet library paths."""
    parser = argparse.ArgumentParser(prog=PROGRAM, description=__doc__)
    parser.add_argument("src", nargs="?", default=DEFAULT_SRC,
                        help=f"directory to sweep for entrypoints (default: {DEFAULT_SRC})")
    parser.add_argument("-J", "--jpath", action="append", default=None,
                        help=f"jsonnet library path, repeatable (default: {DEFAULT_JPATH})")
    return parser.parse_args()


def rel(path: Path) -> str:
    """The path as written in an error, shortened to the repo root when it is inside it."""
    return str(path.relative_to(REPO_ROOT)) if path.is_relative_to(REPO_ROOT) else str(path)


def under_root(path: str) -> Path:
    """Resolve a path against the repo root, leaving an absolute one as given."""
    return Path(path) if Path(path).is_absolute() else REPO_ROOT / path


def entrypoints(src: Path) -> list[Path]:
    """Every .jsonnet under src, skipping dot-prefixed directories."""
    return sorted(
        path for path in src.rglob("*.jsonnet")
        if not any(part.startswith(".") for part in path.relative_to(src).parts)
    )


def is_generated(path: Path) -> bool:
    """Whether this build owns the file -- i.e. it carries the header on line one."""
    try:
        with path.open() as handle:
            return handle.readline().startswith(MARKER)
    except (OSError, UnicodeDecodeError):
        # A binary file (a stray .DS_Store) reads as hand-written, which is the safe
        # side: the build neither deletes it nor overwrites it.
        return False


def generated_files(src: Path) -> list[Path]:
    """Every file under src carrying the generated header, skipping dot-prefixed dirs.

    A retired stack is parked under `.old/`, which entrypoints() also skips -- so its
    committed output is left alone rather than removed as stale.
    """
    return sorted(
        path for path in src.rglob("*")
        if path.is_file()
        and not any(part.startswith(".") for part in path.relative_to(src).parts[:-1])
        and is_generated(path)
    )


def render(entrypoint: Path, jpaths: list[Path]) -> dict[Path, str]:
    """Evaluate one entrypoint to the files it names.

    The asserts are in jsonnet rather than Python so a failure names the entrypoint at the
    point jsonnet already reports line numbers for. Requiring every field to be an object
    is what catches the mistake this shape invites: handing back a bare document instead of
    a map of them, whose scalar and array fields would otherwise become one-line files.

    Args:
        entrypoint: The .jsonnet file to evaluate.
        jpaths: Directories `import` resolves against, after the importing file's own.

    Returns:
        {output path: YAML body}, one entry per top-level field. Bodies carry no generated
        header; each ends in a newline, which jsonnet's own `-S` would have appended and
        the JSON envelope this uses instead does not.
    """
    document = (
        f"assert std.isObject(doc[k]) :"
        f" '{entrypoint.name}: field ' + k + ' must be an object -- an entrypoint returns"
        f" a map of filename to document, not a document';"
        " std.manifestYamlDoc(doc[k], indent_array_in_object=true, quote_keys=false)"
    )
    expression = (
        f"local doc = import '{entrypoint}';"
        f" assert std.isObject(doc) && doc != {{}} :"
        f" '{entrypoint.name}: must evaluate to a non-empty object whose fields name the"
        f" files to write';"
        f" {{ [k]: ({document}) for k in std.objectFields(doc) }}"
    )
    flags = [flag for jpath in jpaths for flag in ("-J", str(jpath))]
    try:
        result = subprocess.run(["jsonnet", *flags, "-e", expression],
                                check=True, capture_output=True, text=True)
    except FileNotFoundError:
        die("jsonnet not found on PATH (run `mise install`)")
    except subprocess.CalledProcessError as error:
        sys.stderr.write(error.stderr)
        die(f"jsonnet failed on {entrypoint}")

    documents = json.loads(result.stdout)
    for stem in documents:
        if not STEM.fullmatch(stem):
            die(f"{rel(entrypoint)}: field {stem!r} is not a usable filename"
                " (letters, digits, dot, dash, underscore; no slash, no leading dot)")
    return {entrypoint.parent / f"{stem}.yaml": f"{body}\n" for stem, body in documents.items()}


def build(sources: list[Path], jpaths: list[Path]) -> dict[Path, tuple[str, str]]:
    """Render every entrypoint into {output path: (source filename, YAML body)}.

    Nothing is written here: the whole output set exists in memory before the tree is
    touched, so a jsonnet failure aborts with the tree as it was. Two entrypoints claiming
    one output is a hard error -- nothing but the fields they declare keeps them apart.
    """
    built: dict[Path, tuple[str, str]] = {}
    for source in sources:
        for path, body in render(source, jpaths).items():
            if path in built:
                die(f"{rel(path)} claimed by both {built[path][0]} and {source.name}")
            built[path] = (source.name, body)
    return built


def main() -> None:
    """Render every entrypoint, remove what the build no longer produces, list both."""
    args = parse_args()
    src = under_root(args.src)
    if not src.is_dir():
        die(f"no such directory: {src}")
    jpaths = [under_root(p) for p in (args.jpath or [DEFAULT_JPATH])]

    sources = entrypoints(src)
    if not sources:
        die(f"no .jsonnet entrypoints under {src}")

    built = build(sources, jpaths)

    clashes = [path for path in built if path.exists() and not is_generated(path)]
    if clashes:
        die("would overwrite hand-written files (rename the entrypoint or the file): "
            + ", ".join(rel(p) for p in sorted(clashes)))

    stale = [path for path in generated_files(src) if path not in built]
    for path in stale:
        path.unlink()

    for path, (source, body) in built.items():
        path.write_text(f"{MARKER}{source} by {PROGRAM} — DO NOT EDIT.\n" + body)

    for path in sorted(stale) + sorted(built):
        print(rel(path))
    print(f"{PROGRAM}: {len(built)} rendered, {len(stale)} stale removed", file=sys.stderr)


if __name__ == "__main__":
    main()
