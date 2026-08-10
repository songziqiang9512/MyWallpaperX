#!/usr/bin/env python3
"""Select and optionally run the smallest repository gates for a Scene change."""

from __future__ import annotations

import argparse
import fnmatch
import json
import subprocess
import sys
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any, Sequence


ROOT = Path(__file__).resolve().parents[1]
REGISTRY_PATH = Path(__file__).with_name("scene_validation_gates.json")
PHASES = ("inner", "checkpoint", "integration", "milestone")
SCENE_SOURCE_PREFIX = "MyWallpaperX/Core/SteamWorkshopScene/"
PRODUCT_PREFIXES = ("MyWallpaperX/", "MyWallpaperX.xcodeproj/")


@dataclass(frozen=True)
class Gate:
    gate_id: str
    command: tuple[str, ...] | None
    reason: str
    serialized: bool
    unresolved: str | None = None


def load_registry(path: Path = REGISTRY_PATH) -> dict[str, Any]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if payload.get("schema_version") != 1:
        raise ValueError("Scene validation registry schema must be 1")
    gates = payload.get("gates")
    groups = payload.get("path_groups")
    if not isinstance(gates, dict) or not isinstance(groups, list):
        raise ValueError("Scene validation registry is malformed")
    required = {"risk", "trigger", "cost", "serialized", "retirement"}
    for gate_id, metadata in gates.items():
        if not isinstance(metadata, dict) or set(metadata) != required:
            raise ValueError(f"Scene validation gate metadata is incomplete: {gate_id}")
        if any(metadata[key] in (None, "") for key in required):
            raise ValueError(f"Scene validation gate metadata is empty: {gate_id}")
    return payload


def changed_paths(base: str, explicit_paths: Sequence[str]) -> list[str]:
    if explicit_paths:
        return sorted(set(path.strip("/") for path in explicit_paths if path.strip("/")))
    completed = subprocess.run(
        ["git", "diff", "--name-only", "--diff-filter=ACDMRTUXB", base],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    paths = {line for line in completed.stdout.splitlines() if line}
    untracked = subprocess.run(
        ["git", "ls-files", "--others", "--exclude-standard"],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    paths.update(line for line in untracked.stdout.splitlines() if line)
    return sorted(paths)


def mapped_tests(
    paths: Sequence[str],
    registry: dict[str, Any],
) -> tuple[set[str], set[str], set[str]]:
    modules: set[str] = set()
    keywords: set[str] = set()
    groups: set[str] = set()
    for path in paths:
        if path.startswith("script/tests/test_") and path.endswith(".py"):
            # Deleted tests still appear in a diff, but cannot be passed to the
            # executable test runner as module names.
            if (ROOT / path).is_file():
                modules.add(Path(path).stem)
        elif path.startswith("script/") and path.endswith(".py"):
            counterpart = ROOT / "script/tests" / f"test_{Path(path).name}"
            if counterpart.is_file():
                modules.add(counterpart.stem)
        for group in registry["path_groups"]:
            patterns = group.get("patterns", [])
            if any(fnmatch.fnmatch(path, pattern) for pattern in patterns):
                groups.add(str(group["id"]))
                modules.update(str(value) for value in group.get("modules", []))
                keywords.update(str(value) for value in group.get("keywords", []))
    return modules, keywords, groups


def focused_test_command(
    modules: set[str],
    keywords: set[str],
) -> tuple[str, ...] | None:
    if not modules and not keywords:
        return None
    command = [sys.executable, "-B", "script/run_scene_tests.py", "--scope", "scene"]
    if modules and not keywords:
        # --module appends to the scope selection; an impossible keyword first
        # makes a modules-only plan genuinely focused.
        command.extend(("-k", "__scene_validation_no_scope_match__"))
    for keyword in sorted(keywords):
        command.extend(("--keyword", keyword))
    for module in sorted(modules):
        command.extend(("--module", module))
    return tuple(command)


def runtime_command(
    args: argparse.Namespace,
    matrix: str,
    *,
    selected_samples: bool,
) -> tuple[str, ...] | None:
    if not args.sample_root or not args.output_dir:
        return None
    command = [
        sys.executable,
        "script/scene_wallpaper_benchmark.py",
        "--app",
        str(args.app),
        "--sample-root",
        str(args.sample_root),
        "--matrix",
        matrix,
        "--output-dir",
        str(args.output_dir),
    ]
    if selected_samples:
        for sample_id in args.sample_id:
            command.extend(("--sample-id", sample_id))
    return tuple(command)


def build_plan(
    paths: Sequence[str],
    args: argparse.Namespace,
    registry: dict[str, Any],
) -> tuple[list[Gate], set[str]]:
    modules, keywords, groups = mapped_tests(paths, registry)
    phase_index = PHASES.index(args.phase)
    scene_source = any(path.startswith(SCENE_SOURCE_PREFIX) for path in paths)
    swift_change = any(path.endswith(".swift") for path in paths)
    product_change = any(path.startswith(PRODUCT_PREFIXES) for path in paths)
    build_required = phase_index >= 1 and product_change
    gates: list[Gate] = []

    focused = focused_test_command(modules, keywords)
    if focused is not None and not (phase_index >= 2 and scene_source):
        gates.append(Gate(
            "focused-tests",
            focused,
            "changed paths map to focused executable test groups",
            False,
        ))
    if phase_index >= 2 and scene_source:
        gates.append(Gate(
            "scene-all-tests",
            (sys.executable, "-B", "script/run_scene_tests.py", "--scope", "scene"),
            "integration of shared Scene source requires the complete executable suite",
            False,
        ))

    if build_required:
        if args.ci:
            if swift_change:
                gates.append(Gate(
                    "code-health",
                    (
                        sys.executable,
                        "script/check_code_health.py",
                        "--check",
                        "--base-ref",
                        args.base,
                    ),
                    "CI xcodebuild does not include the Swift ratchet",
                    False,
                ))
            gates.append(Gate(
                "build-verify",
                (
                    "xcodebuild",
                    "-project",
                    "MyWallpaperX.xcodeproj",
                    "-scheme",
                    "MyWallpaperX",
                    "-configuration",
                    "Debug",
                    "-derivedDataPath",
                    ".codex/DerivedData",
                    "CODE_SIGNING_ALLOWED=NO",
                    "build",
                ),
                "product or project files changed",
                True,
            ))
        else:
            gates.append(Gate(
                "build-verify",
                ("script/build_and_run.sh", "verify"),
                "product or project files changed; the wrapper also satisfies code health",
                True,
            ))
    elif swift_change:
        gates.append(Gate(
            "code-health",
            (
                sys.executable,
                "script/check_code_health.py",
                "--check",
                "--base-ref",
                args.base,
            ),
            "Swift changed without a selected build wrapper",
            False,
        ))

    if phase_index >= 2 and scene_source:
        if args.skip_runtime:
            gates.append(Gate(
                "targeted-sample",
                None,
                f"runtime gate explicitly unavailable: {args.reason}",
                True,
            ))
        else:
            command = runtime_command(
                args,
                "script/scene_wallpaper_full_sample_matrix.json",
                selected_samples=True,
            )
            unresolved = None
            if not args.sample_id:
                unresolved = "integration requires at least one --sample-id"
            elif command is None:
                unresolved = "integration requires --sample-root and --output-dir"
            gates.append(Gate(
                "targeted-sample",
                command,
                "real isolated evidence is required for the affected Scene path",
                True,
                unresolved,
            ))

    if args.phase == "milestone" and args.matrix_tier:
        matrix = (
            "script/scene_wallpaper_sample_matrix.json"
            if args.matrix_tier == "fixed"
            else "script/scene_wallpaper_full_sample_matrix.json"
        )
        command = runtime_command(args, matrix, selected_samples=False)
        unresolved = None if command else "matrix gate requires --sample-root and --output-dir"
        gates.append(Gate(
            "fixed13" if args.matrix_tier == "fixed" else "full45",
            command,
            args.reason,
            True,
            unresolved,
        ))
    return gates, groups


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", default="HEAD")
    parser.add_argument("--phase", choices=PHASES, default="checkpoint")
    parser.add_argument("--path", action="append", default=[])
    parser.add_argument("--run", action="store_true")
    parser.add_argument("--ci", action="store_true")
    parser.add_argument("--format", choices=("text", "json"), default="text")
    parser.add_argument("--sample-id", action="append", default=[])
    parser.add_argument("--sample-root", type=Path)
    parser.add_argument("--output-dir", type=Path)
    parser.add_argument(
        "--app",
        type=Path,
        default=Path(".codex/DerivedData/Build/Products/Debug/MyWallpaperX.app/Contents/MacOS/MyWallpaperX"),
    )
    parser.add_argument("--matrix-tier", choices=("fixed", "full"))
    parser.add_argument("--skip-runtime", action="store_true")
    parser.add_argument("--reason", default="")
    args = parser.parse_args(argv)
    if args.skip_runtime and (not args.ci or not args.reason):
        parser.error("--skip-runtime is CI-only and requires --reason")
    if args.matrix_tier and (args.phase != "milestone" or not args.reason):
        parser.error("--matrix-tier requires milestone phase and --reason")
    return args


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    registry = load_registry()
    paths = changed_paths(args.base, args.path)
    gates, groups = build_plan(paths, args, registry)
    payload = {
        "phase": args.phase,
        "base": args.base,
        "paths": paths,
        "groups": sorted(groups),
        "gates": [asdict(gate) for gate in gates],
    }
    if args.format == "json":
        print(json.dumps(payload, ensure_ascii=False, indent=2))
    else:
        print(f"phase: {args.phase}")
        print("paths:", ", ".join(paths) if paths else "(none)")
        print("groups:", ", ".join(sorted(groups)) if groups else "(none)")
        for gate in gates:
            command = " ".join(gate.command) if gate.command else "(no command)"
            suffix = f"; BLOCKED: {gate.unresolved}" if gate.unresolved else ""
            print(f"- {gate.gate_id}: {command} — {gate.reason}{suffix}")
    if not args.run:
        return 0
    unresolved = [gate for gate in gates if gate.unresolved]
    if unresolved:
        print("validation plan has unresolved required gates", file=sys.stderr)
        return 2
    for gate in gates:
        if gate.command is None:
            continue
        print(f"running {gate.gate_id}: {' '.join(gate.command)}", flush=True)
        completed = subprocess.run(gate.command, cwd=ROOT)
        if completed.returncode != 0:
            return completed.returncode
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
