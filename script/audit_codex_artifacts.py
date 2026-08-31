#!/usr/bin/env python3
"""Report protected .codex paths and unprotected entries that require review."""

from __future__ import annotations

import argparse
import json
import re
import subprocess
from pathlib import Path

from scene_real_test_fixture_config import load_fixture_config


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
CODEX_ROOT = REPOSITORY_ROOT / ".codex"
FIXTURE_CONFIG = REPOSITORY_ROOT / "script/scene_real_test_fixture.json"
ALWAYS_KEEP = (
    CODEX_ROOT / "config.toml",
    CODEX_ROOT / "environments",
    CODEX_ROOT / "scene_real_test_fixture.local.json",
)
CONDITIONAL_REVIEW = (CODEX_ROOT / "DerivedData",)
REFERENCE_SCAN_PATHS = ("docs", "README.md", "AGENTS.md")
CODEX_REFERENCE_PATTERN = re.compile(r"\.codex/[A-Za-z0-9._/-]+")


def required_paths() -> tuple[list[Path], list[str]]:
    config = load_fixture_config(FIXTURE_CONFIG, REPOSITORY_ROOT)
    configured = [
        Path(value).resolve()
        for key, value in config.items()
        if key != "schema_version" and isinstance(value, str)
    ]
    return [*ALWAYS_KEEP, *configured], [
        str(FIXTURE_CONFIG.relative_to(REPOSITORY_ROOT))
    ]


def tracked_reference_files(repository_root: Path) -> list[Path]:
    completed = subprocess.run(
        [
            "/usr/bin/git",
            "-C",
            str(repository_root),
            "ls-files",
            "-z",
            "--",
            *REFERENCE_SCAN_PATHS,
        ],
        capture_output=True,
        check=True,
    )
    return [
        repository_root / relative.decode("utf-8")
        for relative in completed.stdout.split(b"\0")
        if relative
    ]


def codex_reference_paths(
    files: list[Path],
    repository_root: Path,
    codex_root: Path,
) -> list[Path]:
    resolved_codex_root = codex_root.resolve()
    references: set[Path] = set()
    for file in files:
        try:
            text = file.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue
        for match in CODEX_REFERENCE_PATTERN.finditer(text):
            relative = match.group(0).rstrip(".,;:!?，。；：！？")
            candidate = (repository_root / relative).resolve()
            if (
                candidate == resolved_codex_root
                or resolved_codex_root in candidate.parents
            ):
                references.add(candidate)
    return sorted(references)


def referenced_codex_paths(
    files: list[Path],
    repository_root: Path,
    codex_root: Path,
) -> list[Path]:
    return [
        path
        for path in codex_reference_paths(files, repository_root, codex_root)
        if path.exists()
    ]


def partition_entries(
    root: Path,
    protected_paths: list[Path],
) -> tuple[list[Path], list[Path]]:
    protected = {path.resolve() for path in protected_paths}
    kept: list[Path] = []
    candidates: list[Path] = []

    def visit(path: Path) -> None:
        resolved = path.resolve()
        if resolved in protected:
            kept.append(path)
            return
        if any(resolved in required.parents for required in protected):
            if path.is_dir():
                for child in sorted(path.iterdir(), key=lambda item: item.name):
                    visit(child)
            return
        candidates.append(path)

    for entry in sorted(root.iterdir(), key=lambda path: path.name):
        visit(entry)
    return kept, candidates


def allocated_kib(path: Path) -> int:
    completed = subprocess.run(
        ["/usr/bin/du", "-sk", str(path)],
        capture_output=True,
        check=True,
        text=True,
    )
    return int(completed.stdout.split(maxsplit=1)[0])


def inventory() -> dict[str, object]:
    runtime_protected, keep_sources = required_paths()
    reference_files = tracked_reference_files(REPOSITORY_ROOT)
    all_documented = codex_reference_paths(
        reference_files,
        REPOSITORY_ROOT,
        CODEX_ROOT,
    )
    documented = [path for path in all_documented if path.exists()]
    missing_documented = [path for path in all_documented if not path.exists()]
    protected = list(dict.fromkeys(runtime_protected))
    kept, candidates = partition_entries(CODEX_ROOT, protected)

    runtime_set = {path.resolve() for path in runtime_protected}
    conditional_review_set = {path.resolve() for path in CONDITIONAL_REVIEW}

    def describe(path: Path) -> dict[str, object]:
        item: dict[str, object] = {
            "path": str(path.relative_to(REPOSITORY_ROOT)),
            "allocated_kib": allocated_kib(path),
            "kind": "directory" if path.is_dir() else "file",
        }
        resolved = path.resolve()
        protections: list[str] = []
        if resolved in runtime_set:
            protections.append("runtime-required")
        if protections:
            item["protections"] = protections
        if resolved in conditional_review_set:
            item["review_conditions"] = [
                "active-build-writer",
                "running-app-or-daemon-using-this-build",
                "current-batch-rebuild-need",
            ]
        return item

    kept_items = [describe(path) for path in kept]
    candidate_items = [describe(path) for path in candidates]
    return {
        "schema_version": 4,
        "codex_root": str(CODEX_ROOT),
        "keep_sources": keep_sources,
        "reference_scan_paths": list(REFERENCE_SCAN_PATHS),
        "conditional_review_paths": [
            str(path.relative_to(REPOSITORY_ROOT)) for path in CONDITIONAL_REVIEW
        ],
        "tracked_reference_file_count": len(reference_files),
        "documented_reference_count": len(all_documented),
        "documented_path_count": len(documented),
        "documented_paths": [
            str(path.relative_to(REPOSITORY_ROOT)) for path in documented
        ],
        "missing_documented_paths": [
            str(path.relative_to(REPOSITORY_ROOT)) for path in missing_documented
        ],
        "candidate_policy": {
            "classification": "review-required",
            "deletion_authorized": False,
            "meaning": (
                "candidate paths are not protected by the current fixture config "
                "or explicit runtime keep list; they are not proven stale"
            ),
            "tracked_prose_is_provenance_only": True,
            "required_checks_before_cleanup": [
                "active-writer-or-open-handle",
                "batch-ownership",
                "unique-failure-evidence",
                "rebuild-or-recovery-path",
                "exact-user-confirmation-for-material-deletion",
            ],
        },
        "protected": kept_items,
        "candidates": candidate_items,
        "summary": {
            "protected_count": len(kept_items),
            "candidate_count": len(candidate_items),
            "missing_documented_path_count": len(missing_documented),
            "protected_kib": sum(
                int(item["allocated_kib"]) for item in kept_items
            ),
            "candidate_kib": sum(
                int(item["allocated_kib"]) for item in candidate_items
            ),
        },
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--json", action="store_true", help="print the full JSON manifest")
    parser.add_argument(
        "--fail-on-candidates",
        action="store_true",
        help=(
            "exit 1 when review candidates remain; this does not prove they are "
            "stale or safe to delete"
        ),
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    report = inventory()
    if args.json:
        print(json.dumps(report, ensure_ascii=False, indent=2))
    else:
        summary = report["summary"]
        candidate_gib = int(summary["candidate_kib"]) / 1024 / 1024
        kept_gib = int(summary["protected_kib"]) / 1024 / 1024
        print(
            f".codex protected={kept_gib:.2f} GiB "
            f"review-candidates={candidate_gib:.2f} GiB "
            f"({summary['candidate_count']} entries)"
        )
        print("review candidates are not deletion-authorized; inspect ownership and active use")
        for item in sorted(
            report["candidates"],
            key=lambda value: int(value["allocated_kib"]),
            reverse=True,
        ):
            print(
                f"{int(item['allocated_kib']) / 1024 / 1024:8.2f} GiB  "
                f"{item['path']}"
            )
    return 1 if args.fail_on_candidates and report["candidates"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
