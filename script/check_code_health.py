#!/usr/bin/env python3
"""Enforce one 1000-line limit for every managed Swift source file."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path, PurePosixPath
from typing import Any


REPO_ROOT = Path(__file__).resolve().parents[1]
BASELINE_RELATIVE_PATH = Path("script/code_health_baseline.json")
BASELINE_PATH = REPO_ROOT / BASELINE_RELATIVE_PATH
HARD_LINE_LIMIT = 1000
CURRENT_SCHEMA = 4


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="validate the source tree (default)")
    parser.add_argument("--base-ref", help="Git ref used to verify source-root coverage")
    parser.add_argument("--format", choices=("text", "github"), default="text")
    return parser.parse_args()


def validate_repo_relative_path(value: Any, source: str) -> None:
    if not isinstance(value, str) or not value:
        raise ValueError(f"{source} contains an invalid repository path: {value!r}")
    path = PurePosixPath(value)
    if (path.is_absolute() or path.as_posix() != value or ".." in path.parts
            or value == "." or any(character in value for character in "*?[]")):
        raise ValueError(f"{source} path must be normalized and repository-relative: {value!r}")


def read_baseline_text(text: str, source: str) -> dict[str, Any]:
    try:
        baseline = json.loads(text)
    except json.JSONDecodeError as error:
        raise ValueError(f"{source} is not valid JSON: {error}") from error
    if not isinstance(baseline, dict):
        raise ValueError(f"{source} must be an object")
    version = baseline.get("schemaVersion")
    if type(version) is not int or version not in (1, 2, 3, CURRENT_SCHEMA):
        raise ValueError(f"{source} has an unsupported schemaVersion")
    roots = baseline.get("sourceRoots")
    if (not isinstance(roots, list) or not roots
            or any(not isinstance(root, str) or not root for root in roots)
            or len(roots) != len(set(roots))):
        raise ValueError(f"{source} sourceRoots must be a non-empty list of unique paths")
    for root in roots:
        validate_repo_relative_path(root, source)
    if version == CURRENT_SCHEMA:
        unknown = set(baseline) - {"schemaVersion", "hardLineLimit", "sourceRoots", "policy"}
        if unknown:
            raise ValueError(f"{source} has unsupported policy fields: {', '.join(sorted(unknown))}")
        if type(baseline.get("hardLineLimit")) is not int or baseline["hardLineLimit"] != HARD_LINE_LIMIT:
            raise ValueError(f"{source} hardLineLimit must be exactly {HARD_LINE_LIMIT}; no exceptions")
    else:
        # Read-only historical input. The user-authorized schema 4 replacement
        # retires review thresholds and per-file/family locks, not source roots.
        limit = baseline.get("lineLimit" if version == 1 else "hardLineLimit")
        if type(limit) is not int or limit <= 0:
            raise ValueError(f"{source} historical line limit must be a positive integer")
    return baseline


def load_current_baseline() -> dict[str, Any]:
    try:
        text = BASELINE_PATH.read_text(encoding="utf-8")
    except OSError as error:
        raise ValueError(f"cannot read {BASELINE_RELATIVE_PATH}: {error}") from error
    baseline = read_baseline_text(text, str(BASELINE_RELATIVE_PATH))
    if baseline["schemaVersion"] != CURRENT_SCHEMA:
        raise ValueError(f"{BASELINE_RELATIVE_PATH} must use schemaVersion {CURRENT_SCHEMA}")
    return baseline


def belongs_to_source_root(path: str, source_roots: list[str]) -> bool:
    parts = PurePosixPath(path).parts
    return any(parts[:len(PurePosixPath(root).parts)] == PurePosixPath(root).parts
               for root in source_roots)


def swift_line_counts(baseline: dict[str, Any]) -> dict[str, int]:
    for relative_root in baseline["sourceRoots"]:
        if not (REPO_ROOT / relative_root).is_dir():
            raise ValueError(f"configured source root does not exist: {relative_root}")
    result = subprocess.run(
        ["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard", "--", "*.swift"],
        cwd=REPO_ROOT, capture_output=True, check=False,
    )
    if result.returncode != 0:
        raise ValueError(f"git ls-files failed with exit code {result.returncode}")
    try:
        paths = sorted({raw.decode("utf-8") for raw in result.stdout.split(b"\0") if raw})
    except UnicodeDecodeError as error:
        raise ValueError(f"Swift source path is not valid UTF-8: {error}") from error
    unmanaged = [path for path in paths if not belongs_to_source_root(path, baseline["sourceRoots"])]
    if unmanaged:
        raise ValueError("Swift files are outside configured sourceRoots: " + ", ".join(unmanaged))
    counts = {}
    for relative in paths:
        path = REPO_ROOT / relative
        if not path.is_file():
            continue  # Deleted tracked files have no current body to measure.
        try:
            counts[relative] = len(path.read_text(encoding="utf-8").splitlines())
        except (OSError, UnicodeDecodeError) as error:
            raise ValueError(f"cannot read {relative}: {error}") from error
    return counts


def current_tree_findings(baseline: dict[str, Any], counts: dict[str, int]) -> list[tuple[str, str]]:
    # Validate the policy even for callers using in-memory data.
    read_baseline_text(json.dumps(baseline), str(BASELINE_RELATIVE_PATH))
    if baseline["schemaVersion"] != CURRENT_SCHEMA:
        raise ValueError("historical baselines cannot govern the current source tree")
    return [(path, f"file has {count} lines; hard limit is {HARD_LINE_LIMIT}")
            for path, count in counts.items() if count > HARD_LINE_LIMIT]


def baseline_at_ref(base_ref: str) -> tuple[dict[str, Any] | None, str | None]:
    commit = subprocess.run(
        ["git", "rev-parse", "--verify", f"{base_ref}^{{commit}}"],
        cwd=REPO_ROOT, capture_output=True, text=True, check=False,
    )
    if commit.returncode != 0:
        raise ValueError(f"base ref is not a commit: {base_ref}")
    resolved = commit.stdout.strip()
    listing = subprocess.run(
        ["git", "ls-tree", "--name-only", resolved, "--", BASELINE_RELATIVE_PATH.as_posix()],
        cwd=REPO_ROOT, capture_output=True, text=True, check=False,
    )
    if listing.returncode != 0:
        raise ValueError(f"cannot inspect code-health baseline at {base_ref}")
    if not listing.stdout.strip():
        return None, f"{base_ref} predates the code-health baseline; historical source-root check skipped"
    result = subprocess.run(
        ["git", "show", f"{resolved}:{BASELINE_RELATIVE_PATH.as_posix()}"],
        cwd=REPO_ROOT, capture_output=True, text=True, check=False,
    )
    if result.returncode != 0:
        raise ValueError(f"cannot read code-health baseline at {base_ref}")
    return read_baseline_text(result.stdout, f"{base_ref}:{BASELINE_RELATIVE_PATH}"), None


def historical_problems(current: dict[str, Any], previous: dict[str, Any]) -> list[tuple[str, str]]:
    baseline_path = BASELINE_RELATIVE_PATH.as_posix()
    try:
        read_baseline_text(json.dumps(current), baseline_path)
        if current["schemaVersion"] != CURRENT_SCHEMA:
            raise ValueError(f"current policy must use schemaVersion {CURRENT_SCHEMA}")
    except ValueError as error:
        return [(baseline_path, str(error))]
    # Schema 4 is the explicit 2026-10-03 policy replacement: one fixed 1000
    # ceiling, no review threshold or per-file exception/ratchet. Later schema 4
    # baselines still cannot change that ceiling or reduce managed root coverage.
    removed = sorted(set(previous["sourceRoots"]) - set(current["sourceRoots"]))
    return [(baseline_path, f"source roots cannot be removed: {', '.join(removed)}")] if removed else []


def escape_github(value: str) -> str:
    return value.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")


def emit_problem(path: str, message: str, output_format: str) -> None:
    if output_format == "github":
        print(f"::error file={escape_github(path)},line=1,title=Swift file health ERROR::{escape_github(message)}")
    else:
        print(f"ERROR {path}: {message}", file=sys.stderr)


def main() -> int:
    arguments = parse_arguments()
    try:
        baseline = load_current_baseline()
        counts = swift_line_counts(baseline)
        errors = current_tree_findings(baseline, counts)
        if arguments.base_ref:
            previous, notice = baseline_at_ref(arguments.base_ref)
            if notice:
                print(f"NOTICE {notice}")
            if previous is not None:
                errors.extend(historical_problems(baseline, previous))
    except ValueError as error:
        emit_problem(BASELINE_RELATIVE_PATH.as_posix(), str(error), arguments.format)
        return 1
    for path, message in errors:
        emit_problem(path, message, arguments.format)
    if errors:
        return 1
    print(f"Code health passed: {len(counts)} Swift files, {HARD_LINE_LIMIT}-line hard limit; no per-file exceptions.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
