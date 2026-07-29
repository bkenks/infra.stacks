#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["PyYAML>=6"]
# ///
#MISE description="Render every .jsonnet in src/ into files beside it"
"""Render each .jsonnet entrypoint into output files sitting next to it, in src/.

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

The repo root is the -J jpath, so a source at any depth does `import 'lib/lib.libsonnet'`
— the library's single entrypoint. uv resolves PyYAML from the metadata above; the
`jsonnet` binary and uv itself are pinned in .config/mise.toml.

This file lives in .config/mise/tasks/, so mise discovers it as the `render` task (extension
stripped) with no declaration in mise.toml — `mise run render` and
`./.config/mise/tasks/render.py` are the same thing.
"""

import json
import subprocess
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[3]
SRC = ROOT / "src"

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


def entrypoints() -> "list[Path]":
    # Relative to src/ so messages read as the paths a person would type. .libsonnet is
    # not an entrypoint — the library lives in lib/ and is only ever imported.
    return sorted(
        p.relative_to(SRC)
        for p in SRC.rglob("*.jsonnet")
        if p.is_file() and p.name not in SKIP_NAMES
    )


def generated(path: Path) -> bool:
    try:
        with path.open(encoding="utf-8") as fh:
            return fh.readline().startswith(MARKER)
    except (OSError, UnicodeDecodeError):
        return False


def outputs() -> "list[Path]":
    return sorted(p for p in SRC.rglob("*") if p.is_file() and generated(p))


def run_jsonnet(src: Path) -> "dict":
    # stderr inherits, so jsonnet's own message keeps its line numbers. The non-zero exit
    # propagates: that is what makes lefthook's `set -e` abort the commit.
    proc = subprocess.run(
        ["jsonnet", "-J", str(ROOT), str(SRC / src)], stdout=subprocess.PIPE, text=True
    )
    if proc.returncode != 0:
        raise SystemExit(proc.returncode)
    doc = json.loads(proc.stdout)
    if not isinstance(doc, dict) or not doc:
        die(f"{src}: must evaluate to a non-empty object keyed by output filename")
    return doc


def dest(src: Path, key: str) -> Path:
    # An entrypoint renders into its own directory and nowhere else, so a key naming a
    # path rather than a file is a bug in the jsonnet, not a case to support.
    if key != Path(key).name or key in (".", ".."):
        die(f"{src}: output key must be a bare filename, got {key!r}")
    if key in VERBATIM_NAMES:
        return SRC / src.parent / key
    name = Path(key)
    return SRC / src.parent / f"{src.stem}.{name.stem}{name.suffix}"


def body(src: Path, content: "dict | str") -> str:
    if isinstance(content, str):
        return HEADER.format(src=src.name) + content
    return HEADER.format(src=src.name) + yaml.safe_dump(content, width=4096)


def main() -> "None":
    if len(sys.argv) != 1:
        die("usage: render.py  (renders every entrypoint under src/)")

    srcs = entrypoints()
    if not srcs:
        die(f"no .jsonnet entrypoints under {SRC}")

    # Rendered up front, so a jsonnet or YAML failure aborts before anything on disk has
    # been touched.
    rendered: "dict[Path, str]" = {}
    owner: "dict[Path, Path]" = {}
    for src in srcs:
        for key, content in run_jsonnet(src).items():
            path = dest(src, key)
            if path in rendered:
                die(f"{src}: {path.relative_to(SRC)} is already rendered by {owner[path]}")
            rendered[path] = body(src, content)
            owner[path] = src

    stale = [p for p in outputs() if p not in rendered]
    clashes = [p for p in rendered if p.exists() and not generated(p)]
    if clashes:
        die(
            "would overwrite hand-written files (rename the output key or the file): "
            + ", ".join(str(p.relative_to(SRC)) for p in sorted(clashes))
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
