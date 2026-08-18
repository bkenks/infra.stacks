#!/usr/bin/env python3
#MISE description="Render every .jsonnet under a given dir into a .yaml beside it"

"""Render every .jsonnet file under a directory into a .yaml file beside it.

Usage:
    ./render.py [DIRECTORY]

DIRECTORY defaults to the current working directory. Every *.jsonnet file
found underneath it, at any depth, is rendered to a *.yaml file of the same
name in the same directory, overwriting any existing one. Each rendered path
is printed to stdout.

Import resolution:
    `import` statements inside a .jsonnet file are resolved against these
    directories, in order, first match wins:

        1. DIRECTORY itself
        2. each entry of DEFAULT_JPATHS ("lib", then "vendor")
        3. each entry of "jsonnet.languageServer.jpath" in .vscode/settings.json

    DEFAULT_JPATHS and settings.json entries are relative to the current
    working directory, not to DIRECTORY. Run the script from the repo root, or
    use absolute paths, when your library directories live outside DIRECTORY.

    .vscode/settings.json is read from the current working directory. A missing
    file, or a missing "jsonnet.languageServer.jpath" key, contributes no extra
    paths. Malformed JSON is an error.

Requirements:
    The `jsonnet` binary must be on PATH. This repo pins it via mise
    (go-jsonnet in mise.toml); `mise install` provides it.

Exit status:
    0  at least one file rendered, or none found (a warning goes to stderr)
    1  DIRECTORY missing, `jsonnet` not on PATH, or a render failed

A render failure stops the run immediately; files already rendered stay on
disk.

Examples:
    ./render.py         # render everything under $PWD
    ./render.py test    # render the test fixtures
"""

import json
import subprocess
import sys
from pathlib import Path

PROGRAM_NAME = "render.py"

# Baked-in jsonnet import search paths, used alongside the settings.json ones.
DEFAULT_JPATHS = ["lib", "vendor"]

SETTINGS_FILE = Path(".vscode/settings.json")
SETTINGS_JPATH_KEY = "jsonnet.languageServer.jpath"


def warn(message: str) -> None:
    """Print a warning to stderr."""
    print(f"{PROGRAM_NAME}: {message}", file=sys.stderr)


def die(message: str) -> None:
    """Print an error and exit non-zero."""
    warn(message)
    sys.exit(1)


def settings_jpaths() -> list[str]:
    """Read the jsonnet import paths out of .vscode/settings.json.

    Returns:
        The "jsonnet.languageServer.jpath" entries, or an empty list when the
        file or the key is absent.
    """
    if not SETTINGS_FILE.is_file():
        return []

    try:
        settings = json.loads(SETTINGS_FILE.read_text())
    except json.JSONDecodeError as error:
        die(f"{SETTINGS_FILE} is not valid JSON: {error}")

    return settings.get(SETTINGS_JPATH_KEY, [])


def build_jpath_flags(search_root: Path) -> list[str]:
    """Build the -J arguments for jsonnet.

    Order is the search root first, then DEFAULT_JPATHS, then the settings.json
    paths. Earlier paths win when a file exists in several.

    Args:
        search_root: Directory the .jsonnet files are found under.

    Returns:
        The -J flags and their values, ready to pass to jsonnet.
    """
    flags = []
    for path in [str(search_root), *DEFAULT_JPATHS, *settings_jpaths()]:
        if path:
            flags += ["-J", path]
    return flags


def render_to_yaml(jsonnet_file: Path, jpath_flags: list[str]) -> None:
    """Render one .jsonnet file to a .yaml file of the same name in the same directory.

    -S emits the string result raw instead of as a JSON-quoted string.
    -J adds a directory that `import` inside the file resolves against.

    Args:
        jsonnet_file: The .jsonnet file to render.
        jpath_flags: The -J flags from build_jpath_flags.
    """
    yaml_file = jsonnet_file.with_suffix(".yaml")
    expression = (
        f"std.manifestYamlDoc(import '{jsonnet_file}', "
        "indent_array_in_object=true, quote_keys=false)"
    )

    try:
        subprocess.run(
            ["jsonnet", "-S", *jpath_flags, "-o", str(yaml_file), "-e", expression],
            check=True,
        )
    except FileNotFoundError:
        die("jsonnet not found on PATH")
    except subprocess.CalledProcessError as error:
        die(f"jsonnet failed on {jsonnet_file} (exit {error.returncode})")

    print(yaml_file)


def main() -> None:
    """Render every .jsonnet file under the directory given as argv[1], or $PWD."""
    search_root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path.cwd()
    if not search_root.is_dir():
        die(f"no such directory: {search_root}")

    jsonnet_files = sorted(search_root.rglob("*.jsonnet"))
    if not jsonnet_files:
        warn(f"no .jsonnet files under {search_root}")
        return

    jpath_flags = build_jpath_flags(search_root)
    for jsonnet_file in jsonnet_files:
        render_to_yaml(jsonnet_file, jpath_flags)


if __name__ == "__main__":
    main()
