#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Export every Infisical project defined in registry.libsonnet to local JSON backups.

Reads the `projects: { name: 'uuid', ... }` block out of registry.libsonnet (no
jsonnet toolchain required — it's a plain key/value block) and, per project, walks
the full folder tree (`infisical secrets folders get` has no recursive export
equivalent, and `infisical export` itself only reads one folder at a time — this
org keeps every secret in a subfolder like /postgres, never at project root) and
merges each folder's `infisical export` output into one JSON array per project.

Usage:
    ./infisical-export.py
    ./infisical-export.py --output-dir ~/backups/infisical
    ./infisical-export.py --dry-run
"""

import argparse
import json
import re
import shutil
import subprocess
import sys
from datetime import date
from pathlib import Path

REGISTRY_PATH = (
    Path(__file__).resolve().parent.parent / ".jsonnet" / "lib" / "registry.libsonnet"
)

PROJECTS_BLOCK_RE = re.compile(r"projects:\s*\{(.*?)\n\s*\},", re.DOTALL)
PROJECT_ENTRY_RE = re.compile(r"^\s*(\w+):\s*'([0-9a-fA-F-]{36})',?\s*$", re.MULTILINE)


def parse_projects(registry_path: Path) -> dict[str, str]:
    text = registry_path.read_text()
    block_match = PROJECTS_BLOCK_RE.search(text)
    if not block_match:
        sys.exit(f"error: couldn't find a `projects: {{ ... }}` block in {registry_path}")

    projects = dict(PROJECT_ENTRY_RE.findall(block_match.group(1)))
    if not projects:
        sys.exit(f"error: `projects` block in {registry_path} matched but had no entries")
    return projects


def child_folder_paths(project_id: str, env: str, path: str) -> list[str]:
    result = subprocess.run(
        [
            "infisical",
            "secrets",
            "folders",
            "get",
            f"--path={path}",
            f"--env={env}",
            f"--projectId={project_id}",
            "-o",
            "json",
        ],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip())

    folders = json.loads(result.stdout or "[]") or []
    return [
        f["folderPath"].rstrip("/") + "/" + f["folderName"] for f in folders
    ]


def all_folder_paths(project_id: str, env: str) -> list[str]:
    paths = ["/"]
    queue = ["/"]
    while queue:
        current = queue.pop(0)
        children = child_folder_paths(project_id, env, current)
        paths.extend(children)
        queue.extend(children)
    return paths


def export_path(project_id: str, env: str, path: str) -> list[dict]:
    result = subprocess.run(
        [
            "infisical",
            "export",
            f"--projectId={project_id}",
            f"--env={env}",
            f"--path={path}",
            "--format=json",
        ],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip())
    return json.loads(result.stdout or "[]") or []


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--registry",
        type=Path,
        default=REGISTRY_PATH,
        help="path to registry.libsonnet (default: %(default)s)",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path.home() / ".backups" / "infisical",
        help="directory to write export files into (default: ~/.backups/infisical)",
    )
    parser.add_argument(
        "--env",
        default="prod",
        help="Infisical environment slug to export (default: %(default)s)",
    )
    parser.add_argument(
        "--dry-run", action="store_true", help="print the folder paths without exporting"
    )
    args = parser.parse_args()

    if shutil.which("infisical") is None and not args.dry_run:
        sys.exit("error: `infisical` CLI not found on PATH")

    projects = parse_projects(args.registry)
    today = date.today().isoformat()

    args.output_dir.mkdir(parents=True, exist_ok=True)

    failures = []
    for name, project_id in projects.items():
        print(f"[{name}] discovering folders...")
        try:
            paths = all_folder_paths(project_id, args.env)
        except RuntimeError as e:
            print(f"  FAILED to list folders: {e}", file=sys.stderr)
            failures.append(name)
            continue

        print(f"  {len(paths)} folder(s): {', '.join(paths)}")
        if args.dry_run:
            continue

        secrets = []
        try:
            for path in paths:
                secrets.extend(export_path(project_id, args.env, path))
        except RuntimeError as e:
            print(f"  FAILED to export {path}: {e}", file=sys.stderr)
            failures.append(name)
            continue

        out_file = args.output_dir / f"{name}_{project_id}_{today}.json"
        out_file.write_text(json.dumps(secrets, indent=2))
        print(f"  -> {out_file} ({len(secrets)} secret(s))")

    if failures:
        sys.exit(f"\n{len(failures)} project(s) failed to export: {', '.join(failures)}")

    if not args.dry_run:
        print(f"\nDone. {len(projects)} project(s) exported to {args.output_dir}")


if __name__ == "__main__":
    main()
