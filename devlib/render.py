#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# ///
# MISE description="Render every .jsonnet under src/ into the .yaml beside it"

"""Render each .jsonnet entrypoint into the .yaml sitting next to it.

One entrypoint, one output: `services.jsonnet` evaluates to a Compose document and is
written as `services.yaml`. A stack is a directory of those -- `compose.jsonnet` for the
file Compose discovers, `services.jsonnet` for the services themselves, and a
`refs.libsonnet` both import so the two cannot disagree about names.

`*.libsonnet` is never an entrypoint, and a dot-prefixed directory (`.old/`, `.git/`) is
skipped entirely.

Ownership is the header on line one of every generated file. A file without it is
hand-written: it is never deleted, and an entrypoint that would overwrite one is a hard
error. A generated file that the current build no longer produces is removed, which is what
makes a rebuild total -- a deleted stack and a renamed entrypoint leave nothing behind.

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
import subprocess
import sys
from pathlib import Path

PROGRAM = "render.py"

# This exact prefix, first line of the file, is what marks a file as ours to delete and
# rewrite. Changing it orphans every file rendered by an older build, so it must stay
# stable.
MARKER = "# GENERATED from "

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


def render(entrypoint: Path, jpaths: list[Path]) -> str:
    """Evaluate one entrypoint to a YAML document.

    The assert is in jsonnet rather than here so the failure names the entrypoint at the
    point jsonnet already reports line numbers for.

    Args:
        entrypoint: The .jsonnet file to evaluate.
        jpaths: Directories `import` resolves against, after the importing file's own.

    Returns:
        The YAML body, without the generated header.
    """
    flags = [flag for jpath in jpaths for flag in ("-J", str(jpath))]
    expression = (
        f"local doc = import '{entrypoint}';"
        f" assert std.isObject(doc) && doc != {{}} :"
        f" '{entrypoint.name}: must evaluate to a non-empty object';"
        " std.manifestYamlDoc(doc, indent_array_in_object=true, quote_keys=false)"
    )
    try:
        result = subprocess.run(["jsonnet", "-S", *flags, "-e", expression],
                                check=True, capture_output=True, text=True)
    except FileNotFoundError:
        die("jsonnet not found on PATH (run `mise install`)")
    except subprocess.CalledProcessError as error:
        sys.stderr.write(error.stderr)
        die(f"jsonnet failed on {entrypoint}")
    return result.stdout


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

    # Rendered up front so a failure aborts before the tree is touched.
    built = {path.with_suffix(".yaml"): render(path, jpaths) for path in sources}

    clashes = [path for path in built if path.exists() and not is_generated(path)]
    if clashes:
        die("would overwrite hand-written files (rename the entrypoint or the file): "
            + ", ".join(str(p.relative_to(REPO_ROOT)) for p in sorted(clashes)))

    stale = [path for path in generated_files(src) if path not in built]
    for path in stale:
        path.unlink()

    for path, body in built.items():
        header = f"{MARKER}{path.with_suffix('.jsonnet').name} by {PROGRAM} — DO NOT EDIT.\n"
        path.write_text(header + body)

    for path in sorted(stale) + sorted(built):
        print(path.relative_to(REPO_ROOT))
    print(f"{PROGRAM}: {len(built)} rendered, {len(stale)} stale removed", file=sys.stderr)


if __name__ == "__main__":
    main()
