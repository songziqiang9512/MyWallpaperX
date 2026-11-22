#!/usr/bin/env python3
"""Snapshot authored Scene content, excluding App installation metadata."""

from __future__ import annotations

import argparse
import json
import shutil
import sys
from pathlib import Path
from typing import Any


SCRIPT_DIRECTORY = Path(__file__).resolve().parent
if str(SCRIPT_DIRECTORY) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIRECTORY))

from scene_capability_census_io import (
    DERIVED_SAMPLE_NAMES as DERIVED_NAMES,
    iter_sample_directories,
    package_path,
    read_project,
    tree_manifest,
)


def create_snapshot(args: argparse.Namespace) -> int:
    source_root = args.source_root.expanduser().resolve()
    output_root = args.output_root.expanduser().resolve()
    isolated_scene_root = output_root / "Scene"
    if output_root.exists():
        raise FileExistsError(f"output already exists: {output_root}")
    isolated_scene_root.mkdir(parents=True)

    manifest_samples = []
    matrix_samples = []
    skipped = []
    for sample in iter_sample_directories(source_root):
        project_path = sample / "project.json"
        file_digests: dict[Path, str] = {}
        project, project_error = read_project(sample, file_digests=file_digests)
        package = package_path(sample, project)

        destination = isolated_scene_root / sample.name
        shutil.copytree(
            sample,
            destination,
            ignore=shutil.ignore_patterns(*DERIVED_NAMES),
        )
        title = project.get("title") if isinstance(project.get("title"), str) else sample.name
        tree_hash, file_count, byte_count = tree_manifest(sample, file_digests=file_digests)
        sample_manifest = {
            "id": sample.name,
            "title": title,
            "package_file": package.name if package is not None else None,
            "project_sha256": file_digests.get(project_path),
            "package_sha256": file_digests[package] if package is not None else None,
            "tree_sha256": tree_hash,
            "file_count": file_count,
            "byte_count": byte_count,
        }
        manifest_samples.append(sample_manifest)
        matrix_sample = {
            "id": sample.name,
            "title": title,
            "project_sha256": sample_manifest["project_sha256"],
            "package_sha256": sample_manifest["package_sha256"],
            "package_file": sample_manifest["package_file"],
            "tree_sha256": tree_hash,
            "expected_runtime_evidence_schema": args.runtime_evidence_schema,
        }
        if project_error:
            for row in (sample_manifest, matrix_sample):
                row.update(input_status="source-invalid", input_reason_code=project_error)
        matrix_samples.append(matrix_sample)

    manifest = {
        "schema_version": 1,
        "name": args.name,
        "source_root": str(source_root),
        "isolated_root": str(output_root),
        "sample_count": len(manifest_samples),
        "skipped": skipped,
        "samples": manifest_samples,
    }
    matrix = {
        "schema_version": 1,
        "name": f"{args.name}-probe",
        "samples": matrix_samples,
    }
    (output_root / "source-manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    (output_root / "matrix-probe.json").write_text(
        json.dumps(matrix, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(json.dumps({
        "sample_count": len(manifest_samples),
        "skipped": skipped,
        "isolated_root": str(output_root),
        "matrix": str(output_root / "matrix-probe.json"),
    }, ensure_ascii=False))
    return 0


def manifest_mismatches(root: Path, manifest: dict[str, Any]) -> list[dict[str, Any]]:
    changed = []
    for expected in manifest["samples"]:
        sample = root / expected["id"]
        if not sample.is_dir():
            changed.append({"id": expected["id"], "reason": "missing"})
            continue
        actual = tree_manifest(sample)
        wanted = (
            expected["tree_sha256"],
            expected["file_count"],
            expected["byte_count"],
        )
        if actual != wanted:
            changed.append({"id": expected["id"], "actual": actual, "expected": wanted})
    return changed


def verify_snapshot(args: argparse.Namespace) -> int:
    manifest = json.loads(args.manifest.expanduser().resolve().read_text(encoding="utf-8"))
    source_changes = manifest_mismatches(Path(manifest["source_root"]), manifest)
    isolated_changes = manifest_mismatches(
        Path(manifest["isolated_root"]) / "Scene",
        manifest,
    )
    print(json.dumps({
        "sample_count": len(manifest["samples"]),
        "skipped": manifest["skipped"],
        "source_changes": source_changes,
        "isolated_changes": isolated_changes,
    }, ensure_ascii=False, indent=2))
    return 1 if source_changes or isolated_changes else 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    create = subparsers.add_parser("create")
    create.add_argument("--source-root", required=True, type=Path)
    create.add_argument("--output-root", required=True, type=Path)
    create.add_argument("--name", required=True)
    create.add_argument("--runtime-evidence-schema", required=True, type=int)
    create.set_defaults(handler=create_snapshot)
    verify = subparsers.add_parser("verify")
    verify.add_argument("--manifest", required=True, type=Path)
    verify.set_defaults(handler=verify_snapshot)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    return args.handler(args)


if __name__ == "__main__":
    raise SystemExit(main())
