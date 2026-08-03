#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["PyYAML>=6"]
# ///
#MISE description="Render every .jsonnet under a given dir into files beside it"
"""Render each .jsonnet entrypoint into output files sitting next to it.

Generated files are prefixed with the name of the entrypoint that produced them: an
output keyed `config.yaml` in `src/platform/edge/pangolin/files/configs.jsonnet` is
written as `src/platform/edge/pangolin/files/configs.config.yaml`. The rule is entrypoint
stem, key stem, suffix — so `stack.jsonnet` yields `stack.services.yaml`. The source name
leads, so a directory listing sorts every output under the entrypoint that owns it.

The compose filenames in VERBATIM_NAMES are the exception, written under the key as given:
`stack.jsonnet` keyed `compose.yaml` yields `compose.yaml`, not `stack.compose.yaml`. Only
these names are what `docker compose` discovers without -f, and that is worth more than
sorting them beside their entrypoint.

Generated and hand-written files share a directory, so ownership is settled by the
header every generated file starts with. The build sweeps src/ for that header and
deletes what it finds before writing the fresh set, which makes the build total the same
way the old `.deploy/` rmtree was: a deleted stack or a renamed output leaves nothing
behind. A file without the header is hand-written and is never deleted, never
overwritten — an entrypoint that would land on one is an error.

An entrypoint evaluates to {'<filename>': <content>} and may only name bare filenames.
Dict content is dumped as YAML; string content is written verbatim, since the Infisical
fragments carry Go-template bytes that must not be reparsed.

JPATH is the -J jpath, so a source at any depth does `import 'lib/lib.libsonnet'` — the
library's single entrypoint, resolved under JPATH. Repeat `-J`/`--jpath` on the CLI to
override the default and search multiple library roots. uv resolves PyYAML from the
metadata above; the `jsonnet` binary and uv itself are pinned in .config/mise.toml.

ROOT defaults to the nearest ancestor directory containing `.git`, searched up from this
script; if none is found (e.g. a checkout with no `.git`), it falls back to the script's
fixed depth under the repo root.

RENDER_COMPOSE_ROOT, RENDER_COMPOSE_SRC and RENDER_COMPOSE_JPATH (colon-separated, like
PATH) override the built-in defaults for root, src dir and jpath. SRC and JPATH entries
are resolved relative to ROOT; an absolute entry stays as given. `.config/.composonnet.env`
under ROOT sets the same three vars — KEY=VALUE per line, `#` comments — for the common
case of not wanting to export them in a shell. A real environment variable always wins
over the file. The `src` positional argument and `-J`/`--jpath` flag win over env, file
and default alike when given.

`.config/mise.toml` declares this as the `render-compose` task, so `mise run render-compose`
and `./.kmods/jsonnet/scripts/render-compose.py` are the same thing.
"""

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path

import yaml

def _find_git_root(start: Path) -> "Path | None":
    for candidate in (start, *start.parents):
        if (candidate / ".git").exists():
            return candidate
    return None


# Fallback for a checkout without .git (e.g. extracted from a tarball): the script's known
# fixed depth under the repo root.
_DEFAULT_ROOT = _find_git_root(Path(__file__).resolve().parent) or Path(
    __file__
).resolve().parents[3]

ENV_FILE = _DEFAULT_ROOT / ".config" / ".composonnet.env"


def _load_env_file(path: Path) -> "None":
    # setdefault, not assignment: a real environment variable must win over the file.
    if not path.is_file():
        return
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        os.environ.setdefault(key.strip(), value.strip())


_load_env_file(ENV_FILE)

ROOT = (
    Path(os.environ["RENDER_COMPOSE_ROOT"]).resolve()
    if os.environ.get("RENDER_COMPOSE_ROOT")
    else _DEFAULT_ROOT
)

SRC_DEFAULT = (
    (ROOT / os.environ["RENDER_COMPOSE_SRC"]).resolve()
    if os.environ.get("RENDER_COMPOSE_SRC")
    else ROOT / "src"
)

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
# ours to delete and rewrite. Changing it orphans every file rendered by an older build,
# so it is matched by prefix and must stay stable.
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
    if isinstance(content, str):
        return HEADER.format(src=src.name) + content
    return HEADER.format(src=src.name) + yaml.safe_dump(content, width=4096)


def parse_args() -> "argparse.Namespace":
    parser = argparse.ArgumentParser(
        description="Render every .jsonnet in src/ into files beside it"
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
    for path in sorted(stale) + sorted(rendered):
        print(path.relative_to(ROOT))
    print(
        f"render.py: {len(srcs)} entrypoints, {len(rendered)} rendered, "
        f"{len(stale)} stale removed",
        file=sys.stderr,
    )


if __name__ == "__main__":
    main()
