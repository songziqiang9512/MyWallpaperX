#!/usr/bin/env python3
"""Report project .codex entries not required by the current development line."""

from __future__ import annotations

import argparse
import json
import subprocess
from pathlib import Path

from scene_real_test_fixture_config import load_fixture_config


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
CODEX_ROOT = REPOSITORY_ROOT / ".codex"
FIXTURE_CONFIG = REPOSITORY_ROOT / "script/scene_real_test_fixture.json"
ALWAYS_KEEP = (
    CODEX_ROOT / "config.toml",
    CODEX_ROOT / "environments",
    CODEX_ROOT / "DerivedData",
    CODEX_ROOT / "scene_real_test_fixture.local.json",
)


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
    protected, keep_sources = required_paths()
    kept, candidates = partition_entries(CODEX_ROOT, protected)

    def describe(path: Path) -> dict[str, object]:
        return {
            "path": str(path.relative_to(REPOSITORY_ROOT)),
            "allocated_kib": allocated_kib(path),
            "kind": "directory" if path.is_dir() else "file",
        }

    kept_items = [describe(path) for path in kept]
    candidate_items = [describe(path) for path in candidates]
    return {
        "schema_version": 1,
        "codex_root": str(CODEX_ROOT),
        "keep_sources": keep_sources,
        "kept": kept_items,
        "candidates": candidate_items,
        "summary": {
            "kept_count": len(kept_items),
            "candidate_count": len(candidate_items),
            "kept_kib": sum(int(item["allocated_kib"]) for item in kept_items),
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
        help="exit 1 when stale candidates remain",
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
        kept_gib = int(summary["kept_kib"]) / 1024 / 1024
        print(
            f".codex current={kept_gib:.2f} GiB "
            f"stale-candidates={candidate_gib:.2f} GiB "
            f"({summary['candidate_count']} entries)"
        )
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
