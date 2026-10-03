#!/usr/bin/env python3
"""Select repository gates and disclose product sources without focused test mappings."""

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
try:
    from script.source_relocations import unchanged_source_relocations
except ModuleNotFoundError:
    from source_relocations import unchanged_source_relocations


ROOT = Path(__file__).resolve().parents[1]
REGISTRY_PATH = Path(__file__).with_name("scene_validation_gates.json")
PHASES = ("inner", "checkpoint", "integration", "milestone")
GATE_STATUSES = {"planned", "skipped", "blocked", "passed", "failed"}
SCENE_PRODUCT_PATTERNS = (
    "MyWallpaperX/Core/SteamWorkshopScene/**",
    "MyWallpaperX/App/*DebugScenePlaybackRunner*.swift",
    "MyWallpaperX/Modules/SteamWorkshop/Scene/**",
    "MyWallpaperX/Core/Playback/*Scene*",
)
PRODUCT_PREFIXES = (
    "MyWallpaperX/",
    "MyWallpaperX.xcodeproj/",
    "MyWallpaperXHelp/",
    "SteamService/",
    "WallpaperDaemonSources/",
)
PRODUCT_SOURCE_SUFFIXES = {".swift", ".c", ".h", ".m", ".mm", ".metal", ".cs"}
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
        if any(
            not isinstance(metadata[key], str) or not metadata[key].strip()
            for key in required - {"serialized"}
        ) or not isinstance(metadata["serialized"], bool):
            raise ValueError(f"Scene validation gate metadata is empty: {gate_id}")
    for gate_id, selection in payload.get("method_gates", {}).items():
        if gate_id not in gates or selection.get("minimum_phase") not in PHASES:
            raise ValueError(f"invalid method gate registration: {gate_id}")
        if not selection.get("methods") or not selection.get("module") or not selection.get("class"):
            raise ValueError(f"incomplete method gate selection: {gate_id}")
    group_ids: set[str] = set()
    for group in groups:
        if not isinstance(group, dict) or not isinstance(group.get("id"), str):
            raise ValueError("invalid path-group registration")
        group_id = group["id"]
        if not group_id or group_id in group_ids:
            raise ValueError(f"empty or duplicate path-group id: {group_id}")
        group_ids.add(group_id)
        for field in ("patterns", "modules", "keywords"):
            values = group.get(field, [])
            if not isinstance(values, list) or any(
                not isinstance(value, str) or not value.strip() for value in values
            ):
                raise ValueError(f"invalid path-group {field}: {group_id}")
        if not group.get("patterns"):
            raise ValueError(f"path-group has no patterns: {group_id}")
    return payload


def changed_paths(base: str, explicit_paths: Sequence[str]) -> list[str]:
    if explicit_paths:
        return sorted(set(path.strip("/") for path in explicit_paths if path.strip("/")))
    completed = subprocess.run(
        ["git", "diff", "--name-only", "-z", "--no-renames", "--diff-filter=ACDMRTUXB", base],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    paths = {path for path in completed.stdout.split("\0") if path}
    untracked = subprocess.run(
        ["git", "ls-files", "--others", "--exclude-standard", "-z"],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    paths.update(path for path in untracked.stdout.split("\0") if path)
    return sorted(paths)


def select_owned_paths(
    paths: Sequence[str], owned_paths: Sequence[str]
) -> tuple[list[str], list[str]]:
    """Select exact files, retaining excluded changes for audit in every report."""
    if not owned_paths:
        raise ValueError("--owned-path requires at least one exact repository-relative file")
    for path in owned_paths:
        # CLI declarations can contain accidental directory prefixes, globs,
        # absolute paths, traversal or typos; never silently normalize these.
        if (
            not path or path != path.strip() or Path(path).is_absolute()
            or any(part in {"", ".", ".."} for part in path.split("/"))
            or any(character in path for character in "*?[]\\")
            or any(ord(character) < 32 for character in path)
        ):
            raise ValueError(f"invalid --owned-path (expected an exact relative file): {path!r}")
        candidate = ROOT / path
        if not candidate.resolve().is_relative_to(ROOT.resolve()):
            raise ValueError(f"--owned-path escapes the repository: {path!r}")
        if candidate.is_dir() or (not candidate.is_file() and path not in paths):
            raise ValueError(f"--owned-path is not an existing or changed file: {path!r}")
    owned = set(owned_paths)
    selected = sorted(set(paths) & owned)
    if not selected:
        raise ValueError("--owned-path selection contains no changed files")
    return selected, sorted(set(paths) - owned)


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
            if path == "script/run_checkpoint_build.sh":
                modules.add("test_checkpoint_build")
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
                if not group.get("modules"):
                    keywords.update(str(value) for value in group.get("keywords", []))
    return modules, keywords, groups


def focused_test_command(
    modules: set[str],
    keywords: set[str],
) -> tuple[str, ...] | None:
    if not modules and not keywords:
        return None
    command = [sys.executable, "-B", "script/run_scene_tests.py", "--scope", "scene"]
    # mapped_tests resolves fallbacks per group. Keep their union so adding a
    # path with explicit modules cannot discard another group's keyword tests.
    for module in sorted(modules):
        command.extend(("--module", module))
    for keyword in sorted(keywords):
        command.extend(("--keyword", keyword))
    return tuple(command)


def product_test_mapping(
    paths: Sequence[str], registry: dict[str, Any], available_modules: Sequence[str],
) -> dict[str, Any]:
    """Pure registry routing audit; a module association is not behavior coverage.

    Callers supply their inventory and available test module names. Build gates,
    governance method gates and keyword guesses cannot hide a missing explicit
    focused mapping. Results describe only the supplied paths, including deleted
    or hypothetical sources when the caller includes those in a change plan.
    """
    available = set(available_modules)
    method_modules = {item["module"] for item in registry.get("method_gates", {}).values()}
    rows = []
    for path in sorted(set(paths)):
        if not path.startswith(PRODUCT_PREFIXES) or Path(path).suffix not in PRODUCT_SOURCE_SUFFIXES:
            continue
        groups = [group for group in registry["path_groups"] if any(
            fnmatch.fnmatch(path, pattern) for pattern in group.get("patterns", [])
        )]
        modules = {module for group in groups for module in group.get("modules", [])} - method_modules
        rows.append({
            "path": path,
            "groups": sorted(group["id"] for group in groups),
            "selected_modules": sorted(modules & available),
            "missing_modules": sorted(modules - available),
        })
    return {
        "product_paths": [row["path"] for row in rows],
        "mapped_paths": [row["path"] for row in rows if row["selected_modules"]],
        "unmapped_paths": [row["path"] for row in rows if not row["selected_modules"]],
        "stale_modules": sorted({module for row in rows for module in row["missing_modules"]}),
        "mappings": rows,
        "evidence_limit": "Registry associations select existing tests; they do not prove behavior coverage. Build and governance gates do not cover missing focused mappings.",
    }


def is_scene_product_path(path: str) -> bool:
    return any(fnmatch.fnmatch(path, pattern) for pattern in SCENE_PRODUCT_PATTERNS)


def code_health_gate(base: str, reason: str) -> Gate:
    return Gate(
        "code-health",
        (
            sys.executable,
            "script/check_code_health.py",
            "--check",
            "--base-ref",
            base,
        ),
        reason,
        False,
    )


def scene_defense_gate(base: str) -> Gate:
    return Gate(
        "scene-defense",
        (
            sys.executable,
            "script/check_scene_defense.py",
            "--check",
            "--base-ref",
            base,
        ),
        (
            "Scene defensive surface ratchet: zero-caller entries, canonical-helper "
            "copies, and swallowed errors may only shrink"
        ),
        False,
    )


def design_gate(base: str) -> Gate:
    return Gate(
        "design-gate",
        (
            sys.executable,
            "script/check_design_gate.py",
            "--base-ref",
            base,
        ),
        (
            "design-first gate: implementation starts on registered capabilities "
            "(script/design_gated_areas.json) require an approved design doc"
        ),
        False,
    )


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
    missing_modules = sorted(module for module in modules
                             if not (ROOT / "script/tests" / f"{module}.py").is_file())
    if missing_modules:
        raise ValueError("mapped test modules no longer exist: " + ", ".join(missing_modules))
    # These modules have registered method-level gates; never also execute
    # their mixed whole-module form as a focused test.
    modules.difference_update(
        selection["module"] for selection in registry.get("method_gates", {}).values()
    )
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

    if deleted_test:
        # Retiring a test changes discovery/registry wiring, not every product
        # behavior. Keep affected groups and validate that wiring explicitly.
        modules.update({'test_scene_test_runner', 'test_verify_scene_change'})
    focused = focused_test_command(modules, keywords)
    test_scope = getattr(args, "test_scope", "changed")
    if test_scope != "changed":
        gates.append(Gate(
            f"{test_scope}-tests",
            (sys.executable, "-B", "script/run_scene_tests.py", "--scope", test_scope),
            "explicitly selected test scope",
            False,
        ))
    elif focused is not None:
        gates.append(Gate(
            "focused-tests",
            focused,
            "changed paths map to focused executable test groups",
            False,
        ))
    if test_scope == "changed" and args.phase == "milestone" and scene_product_change:
        gates.append(Gate(
            "scene-all-tests",
            (sys.executable, "-B", "script/run_scene_tests.py", "--scope", "scene"),
            "a Scene product milestone requires the complete executable regression suite",
            False,
        ))

    full_suite = any(gate.gate_id in {"all-tests", "scene-all-tests"} for gate in gates)
    for gate_id, selection in registry.get("method_gates", {}).items():
        if full_suite:
            continue
        if phase_index < PHASES.index(selection["minimum_phase"]):
            continue
        if not (
            groups.intersection(selection.get("groups", []))
            or any(fnmatch.fnmatch(path, pattern)
                   for path in paths for pattern in selection.get("patterns", []))
        ):
            continue
        command = (
            sys.executable, "-B", "-m", "unittest",
            *(f"script.tests.{selection['module']}.{selection['class']}.{method}"
              for method in selection["methods"]),
        )
        gates.append(Gate(gate_id, command, registry["gates"][gate_id]["trigger"], False))
    if any(
        fnmatch.fnmatch(path, "script/tests/test_*.py")
        or path in {"script/check_test_assertions.py", "script/test_assertion_baseline.json",
                    "script/scene_validation_gates.json"}
        for path in paths
    ):
        gates.append(Gate(
            "test-assertions",
            (sys.executable, "-B", "script/check_test_assertions.py", "--check", "--base-ref", args.base),
            "Python test declaration-shape assertions may only shrink", False,
        ))
    if any(path.startswith(("script/", "docs/", ".agents/", ".github/")) for path in paths):
        gates.append(Gate(
            "repository-artifacts",
            (sys.executable, "-B", "script/check_repository_artifacts.py", "--check", "--base-ref", args.base),
            "Git-visible tool and documentation files must stay within the artifact size budget", False,
        ))
    if any((path.startswith('MyWallpaperX/Core/SteamWorkshopScene/') and path.endswith('.swift'))
           or (path.startswith('script/tests/') and path.endswith(('.swift', '.py')))
           or path in {'script/check_scene_dependencies.py', 'script/scene_dependency_baseline.json'}
           for path in paths):
        gates.append(Gate('scene-dependencies',
                          (sys.executable, '-B', 'script/check_scene_dependencies.py', '--check', '--base-ref', args.base),
                          registry['gates']['scene-dependencies']['trigger'], False))
    if 'documentation' in groups:
        gates.append(Gate('document-health',
                          (sys.executable, '-B', 'script/document_health.py', '--check', '--base', args.base),
                          registry['gates']['document-health']['trigger'], False))
    if any(path.startswith(PRODUCT_PREFIXES) for path in paths) or 'validation-governance' in groups:
        gates.append(Gate('repository-residue',
                          (sys.executable, '-B', 'script/repository_residue.py', '--check'),
                          registry['gates']['repository-residue']['trigger'], False))

    if args.ci:
        for gate in gates:
            if gate.command and "script/run_scene_tests.py" in gate.command:
                gate.command += ("--fail-fast",)
            elif gate.command and "unittest" in gate.command:
                gate.command += ("--failfast",)

    if build_required:
        if swift_change:
            gates.append(
                code_health_gate(
                    args.base, "the pure build gate does not include the Swift ratchet"
                )
            )
        if scene_product_change:
            gates.append(scene_defense_gate(args.base))
        gates.append(design_gate(args.base))
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
        gates.append(
            code_health_gate(args.base, "Swift changed without a selected build wrapper")
        )
        if scene_product_change:
            gates.append(scene_defense_gate(args.base))
        gates.append(design_gate(args.base))
    elif scene_product_change:
        gates.append(scene_defense_gate(args.base))
        gates.append(design_gate(args.base))
    if product_change and not (build_required or swift_change or scene_product_change):
        gates.append(design_gate(args.base))

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
    for gate in gates:
        if gate.gate_id not in registry["gates"]:
            raise ValueError(f"unregistered validation gate: {gate.gate_id}")
        # Registration is the lifecycle authority for every emitted gate,
        # including computed test-scope IDs and blocked selection gates.
        gate.serialized = registry["gates"][gate.gate_id]["serialized"]
    return gates, groups


def run_gates(gates: Sequence[Gate], base: str = 'HEAD') -> int:
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
        completed = subprocess.run(gate.command, cwd=ROOT,
                                   env={**os.environ, 'MWX_VALIDATION_BASE': base})
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
    registry: dict[str, Any] | None = None,
) -> dict[str, Any]:
    mapping = product_test_mapping(
        paths, registry if registry is not None else load_registry(),
        [path.stem for path in (ROOT / "script/tests").glob("test_*.py")],
    )
    # A byte-identical move has no new behavior to test. Preserve its missing
    # focused mapping in the report; only an actual successful product build
    # can close this relocation, and any subsequent byte edit loses the proof.
    candidates = [path for path in paths if path.endswith('.swift') and path.startswith(PRODUCT_PREFIXES)]
    moves = unchanged_source_relocations(ROOT, args.base, candidates, candidates) if mapping['unmapped_paths'] else {}
    relocation_paths = set(moves) | set(moves.values())
    built = any(gate.gate_id == 'build-verify' and gate.status == 'passed' for gate in gates)
    unresolved_mapping = [path for path in mapping['unmapped_paths'] if not (built and path in relocation_paths)]
    closure_complete = (
        execution == "completed"
        and bool(gates)
        and all(gate.status == "passed" for gate in gates)
        and not unresolved_mapping
        and not mapping["stale_modules"]
    )
    return {
        "phase": args.phase,
        "base": args.base,
        "paths": list(paths),
        "path_selection": (
            "owned-only" if getattr(args, "owned_path", None)
            else "explicit" if args.path else "all-changes"
        ),
        "owned_paths": sorted(set(getattr(args, "owned_path", None) or [])),
        "excluded_paths": list(getattr(args, "excluded_paths", [])),
        "groups": sorted(groups),
        "execution": execution,
        "validation_scope": "structural-only" if args.skip_runtime else "requested",
        "closure_complete": closure_complete,
        "focused_test_mapping": mapping,
        "verified_source_relocations": moves,
        "unresolved_test_mapping": unresolved_mapping,
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
    print(f"path selection: {payload['path_selection']}")
    if payload["path_selection"] == "owned-only":
        print("owned paths:", ", ".join(payload["owned_paths"]))
        print("excluded changed paths:", ", ".join(payload["excluded_paths"]) or "(none)")
    print("groups:", ", ".join(payload["groups"]) if payload["groups"] else "(none)")
    mapping = payload["focused_test_mapping"]
    print("focused mapping:", f"{len(mapping['mapped_paths'])}/{len(mapping['product_paths'])} product sources")
    print("mapping evidence limit:", mapping["evidence_limit"])
    for path in mapping["unmapped_paths"]:
        print(f"- [TEST MAPPING DEBT] {path}")
    for module in mapping["stale_modules"]:
        print(f"- [STALE TEST MAPPING] {module}")
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
    parser.add_argument("--test-scope", choices=("changed", "release", "all"), default="changed")
    selection = parser.add_mutually_exclusive_group()
    selection.add_argument("--path", action="append", default=[])
    selection.add_argument(
        "--owned-path", action="append",
        help="select changed files owned by this batch; repeat exact repository-relative files",
    )
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
    try:
        registry = load_registry()
        paths = changed_paths(args.base, args.path)
        args.excluded_paths = []
        if args.owned_path is not None:
            paths, args.excluded_paths = select_owned_paths(paths, args.owned_path)
        gates, groups = build_plan(paths, args, registry)
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print(f"validation plan error: {error}", file=sys.stderr)
        return 2
    if not args.run:
        print_payload(
            validation_payload(
                args,
                paths,
                groups,
                gates,
                execution="not-run",
                registry=registry,
            ),
            args.format,
        )
        return 0
    return_code = run_gates(gates, args.base)
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
            registry=registry,
        ),
        args.format,
    )
    return return_code


if __name__ == "__main__":
    raise SystemExit(main())
