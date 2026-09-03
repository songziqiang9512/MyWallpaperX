#!/usr/bin/env python3
"""Select and optionally run the smallest repository gates for a Scene change."""

from __future__ import annotations

import argparse
import fnmatch
import json
import os
import subprocess
import sys
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any, Sequence


ROOT = Path(__file__).resolve().parents[1]
REGISTRY_PATH = Path(__file__).with_name("scene_validation_gates.json")
PHASES = ("inner", "checkpoint", "integration", "milestone")
GATE_STATUSES = {"planned", "skipped", "blocked", "passed", "failed"}
SCENE_PRODUCT_PATTERNS = (
    "MyWallpaperX/Core/SteamWorkshopScene/**",
    "MyWallpaperX/App/DebugScenePlaybackRunner*.swift",
    "MyWallpaperX/Modules/SteamWorkshop/Scene/**",
    "MyWallpaperX/Core/Playback/*Scene*",
)
PRODUCT_PREFIXES = (
    "MyWallpaperX/",
    "MyWallpaperX.xcodeproj/",
    "MyWallpaperXHelp/",
    "WallpaperDaemonSources/",
)
ROOT_GOVERNANCE_FILES = {"AGENTS.md", "README.md", ".gitignore"}
RELEASE_WORKFLOW_FILES = {
    ".github/workflows/build.yml",
    ".github/workflows/ci.yml",
}


@dataclass
class Gate:
    gate_id: str
    command: tuple[str, ...] | None
    reason: str
    serialized: bool
    unresolved: str | None = None
    status: str = "planned"
    return_code: int | None = None

    def __post_init__(self) -> None:
        if self.unresolved and self.status == "planned":
            self.status = "blocked"
        if self.status not in GATE_STATUSES:
            raise ValueError(f"invalid Scene validation gate status: {self.status}")


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
        if path in ROOT_GOVERNANCE_FILES:
            groups.add("repository-governance")
            modules.update(
                {
                    "test_document_role_index",
                    "test_scene_governance_contract",
                    "test_scene_semantics_coverage",
                }
            )
        if path in RELEASE_WORKFLOW_FILES:
            groups.add("release-workflow-governance")
            modules.add("test_document_role_index")
        if path in {"script/build_and_run.sh", "script/run_checkpoint_build.sh"}:
            groups.add("build-entrypoint-governance")
            modules.add("test_verify_scene_change")
        if path.startswith(".agents/skills/mywallpaperx-maintainer/"):
            groups.add("repository-skill-governance")
            modules.add("test_scene_governance_contract")
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
    # Explicit registry modules are the reviewed risk boundary.  Keywords are
    # only a fallback for groups that have no executable module mapping; mixing
    # both would silently widen a focused gate to every name-matched module.
    if modules:
        for module in sorted(modules):
            command.extend(("--module", module))
    else:
        for keyword in sorted(keywords):
            command.extend(("--keyword", keyword))
    return tuple(command)


def is_scene_product_path(path: str) -> bool:
    return any(fnmatch.fnmatch(path, pattern) for pattern in SCENE_PRODUCT_PATTERNS)


def runtime_command(
    args: argparse.Namespace,
    matrix: str,
    *,
    selected_samples: bool,
    output_subdirectory: str,
) -> tuple[str, ...] | None:
    if (
        not args.app
        or not args.app.is_file()
        or not os.access(args.app, os.X_OK)
        or not args.sample_root
        or not args.output_dir
    ):
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
        str(args.output_dir / output_subdirectory),
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
    scene_product_change = any(is_scene_product_path(path) for path in paths)
    swift_change = any(path.endswith(".swift") for path in paths)
    product_change = any(path.startswith(PRODUCT_PREFIXES) for path in paths)
    deleted_test = any(
        path.startswith("script/tests/test_")
        and path.endswith(".py")
        and not (ROOT / path).is_file()
        for path in paths
    )
    build_required = phase_index >= 1 and product_change
    unmapped_paths: list[str] = []
    for path in paths:
        path_modules, path_keywords, path_groups = mapped_tests([path], registry)
        deleted_path = (
            path.startswith("script/tests/test_")
            and path.endswith(".py")
            and not (ROOT / path).is_file()
        )
        product_build_path = phase_index >= 1 and path.startswith(PRODUCT_PREFIXES)
        if not (
            path_modules
            or path_keywords
            or path_groups
            or deleted_path
            or product_build_path
        ):
            unmapped_paths.append(path)
    gates: list[Gate] = []

    focused = focused_test_command(modules, keywords)
    if focused is not None:
        gates.append(Gate(
            "focused-tests",
            focused,
            "changed paths map to focused executable test groups",
            False,
        ))
    if deleted_test:
        gates.append(Gate(
            "repository-all-tests",
            (sys.executable, "-B", "script/run_scene_tests.py", "--scope", "all"),
            "a deleted test requires the complete executable repository suite",
            False,
        ))
    elif args.phase == "milestone" and scene_product_change:
        gates.append(Gate(
            "scene-all-tests",
            (sys.executable, "-B", "script/run_scene_tests.py", "--scope", "scene"),
            "a Scene product milestone requires the complete executable regression suite",
            False,
        ))

    if build_required:
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
                "the pure build gate does not include the Swift ratchet",
                False,
            ))
        gates.append(Gate(
            "build-verify",
            ("/bin/bash", "script/run_checkpoint_build.sh"),
            (
                "product or project files changed; checkpoint builds use an isolated, "
                "serialized, self-cleaning DerivedData and do not launch the App"
            ),
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

    if phase_index >= 2 and scene_product_change:
        if args.skip_runtime:
            gates.append(Gate(
                "targeted-sample",
                None,
                f"structural-only: runtime gate explicitly skipped: {args.reason}",
                True,
                status="skipped",
            ))
        else:
            command = runtime_command(
                args,
                "script/scene_wallpaper_full_sample_matrix.json",
                selected_samples=True,
                output_subdirectory="targeted",
            )
            unresolved = None
            if not args.sample_id:
                unresolved = f"{args.phase} requires at least one --sample-id"
            elif not args.app:
                unresolved = (
                    f"{args.phase} requires --app for a frozen staged executable"
                )
            elif not args.app.is_file() or not os.access(args.app, os.X_OK):
                unresolved = f"{args.phase} --app must be an existing executable"
            elif command is None:
                unresolved = f"{args.phase} requires --sample-root and --output-dir"
            gates.append(Gate(
                "targeted-sample",
                command,
                "real isolated evidence is required for the affected Scene path",
                True,
                unresolved,
            ))

    if args.phase == "milestone" and "matrix" in groups and not args.matrix_tier:
        gates.append(Gate(
            "matrix-tier-selection",
            None,
            "matrix or benchmark contract changes require an explicit milestone tier",
            True,
            "choose --matrix-tier fixed|full and provide --reason",
        ))

    if args.phase == "milestone" and args.matrix_tier:
        matrix = (
            "script/scene_wallpaper_sample_matrix.json"
            if args.matrix_tier == "fixed"
            else "script/scene_wallpaper_full_sample_matrix.json"
        )
        command = runtime_command(
            args,
            matrix,
            selected_samples=False,
            output_subdirectory=args.matrix_tier,
        )
        if not args.app:
            unresolved = "matrix gate requires --app for a frozen staged executable"
        elif not args.app.is_file() or not os.access(args.app, os.X_OK):
            unresolved = "matrix gate --app must be an existing executable"
        elif not command:
            unresolved = "matrix gate requires --sample-root and --output-dir"
        else:
            unresolved = None
        gates.append(Gate(
            "fixed13" if args.matrix_tier == "fixed" else "full45",
            command,
            args.reason,
            True,
            unresolved,
        ))
    if unmapped_paths:
        gates.append(Gate(
            "unmapped-change",
            None,
            "every changed path requires an executable gate or explicit registry exemption",
            False,
            (
                "add a path-group mapping or a reviewed no-gate classification for: "
                + ", ".join(unmapped_paths)
            ),
        ))
    return gates, groups


def run_gates(gates: Sequence[Gate]) -> int:
    unresolved = [gate for gate in gates if gate.status == "blocked"]
    if unresolved:
        print("validation plan has unresolved required gates", file=sys.stderr)
        return 2
    for gate in gates:
        if gate.status == "skipped":
            continue
        if gate.command is None:
            gate.status = "blocked"
            gate.unresolved = "required gate has no executable command"
            print("validation plan has a required gate without a command", file=sys.stderr)
            return 2
        print(f"running {gate.gate_id}: {' '.join(gate.command)}", flush=True)
        completed = subprocess.run(gate.command, cwd=ROOT)
        gate.return_code = completed.returncode
        if completed.returncode != 0:
            gate.status = "failed"
            return completed.returncode
        gate.status = "passed"
    return 0


def validation_payload(
    args: argparse.Namespace,
    paths: Sequence[str],
    groups: set[str],
    gates: Sequence[Gate],
    *,
    execution: str,
) -> dict[str, Any]:
    closure_complete = (
        execution == "completed"
        and bool(gates)
        and all(gate.status == "passed" for gate in gates)
    )
    return {
        "phase": args.phase,
        "base": args.base,
        "paths": list(paths),
        "groups": sorted(groups),
        "execution": execution,
        "validation_scope": "structural-only" if args.skip_runtime else "requested",
        "closure_complete": closure_complete,
        "gates": [asdict(gate) for gate in gates],
    }


def print_payload(payload: dict[str, Any], output_format: str) -> None:
    if output_format == "json":
        print(json.dumps(payload, ensure_ascii=False, indent=2))
        return
    print(f"phase: {payload['phase']}")
    print(f"execution: {payload['execution']}")
    print(f"validation scope: {payload['validation_scope']}")
    print(f"closure complete: {'yes' if payload['closure_complete'] else 'no'}")
    print("paths:", ", ".join(payload["paths"]) if payload["paths"] else "(none)")
    print("groups:", ", ".join(payload["groups"]) if payload["groups"] else "(none)")
    for gate in payload["gates"]:
        command = " ".join(gate["command"]) if gate["command"] else "(no command)"
        detail = f"; BLOCKED: {gate['unresolved']}" if gate["unresolved"] else ""
        if gate["status"] == "planned":
            detail += "; not executed"
        print(
            f"- [{gate['status'].upper()}] {gate['gate_id']}: "
            f"{command} — {gate['reason']}{detail}"
        )


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
        help="frozen staged MyWallpaperX executable for integration or milestone runtime evidence",
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
    if not args.run:
        print_payload(
            validation_payload(
                args,
                paths,
                groups,
                gates,
                execution="not-run",
            ),
            args.format,
        )
        return 0
    return_code = run_gates(gates)
    if any(gate.status == "blocked" for gate in gates):
        execution = "blocked"
    elif any(gate.status == "failed" for gate in gates):
        execution = "failed"
    else:
        execution = "completed"
    print_payload(
        validation_payload(
            args,
            paths,
            groups,
            gates,
            execution=execution,
        ),
        args.format,
    )
    return return_code


if __name__ == "__main__":
    raise SystemExit(main())
