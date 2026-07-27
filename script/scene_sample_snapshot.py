#!/usr/bin/env python3
"""Create or verify an isolated Scene sample snapshot and probe matrix."""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
from pathlib import Path
from typing import Any


DERIVED_NAMES = {
    ".DS_Store",
    ".mywallpaperx-scene-interpretation.json",
    ".mywallpaperx-scene-preview-log.txt",
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def package_path(sample: Path, project: dict[str, Any]) -> Path | None:
    raw_entry = project.get("file")
    entry = raw_entry.strip().replace("\\", "/") if isinstance(raw_entry, str) else ""
    entry_name = Path(entry).name if entry else "scene.json"
    derived_name = str(Path(entry_name).with_suffix(".pkg"))
    names = [derived_name] if derived_name == "scene.pkg" else [derived_name, "scene.pkg"]
    return next((sample / name for name in names if (sample / name).is_file()), None)


def tree_manifest(sample: Path) -> tuple[str, int, int]:
    digest = hashlib.sha256()
    count = 0
    byte_count = 0
    for path in sorted(item for item in sample.rglob("*") if item.is_file()):
        if path.name in DERIVED_NAMES:
            continue
        relative = path.relative_to(sample).as_posix()
        payload_hash = sha256(path)
        size = path.stat().st_size
        digest.update(relative.encode("utf-8"))
        digest.update(b"\0")
        digest.update(payload_hash.encode("ascii"))
        digest.update(b"\0")
        digest.update(str(size).encode("ascii"))
        digest.update(b"\n")
        count += 1
        byte_count += size
    return digest.hexdigest(), count, byte_count


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
    for sample in sorted(source_root.iterdir(), key=lambda item: item.name):
        if not sample.is_dir() or not sample.name.isdigit():
            continue
        project_path = sample / "project.json"
        if not project_path.is_file():
            skipped.append({"id": sample.name, "reason": "missing project.json"})
            continue
        project = json.loads(project_path.read_text(encoding="utf-8"))
        package = package_path(sample, project)
        if package is None:
            skipped.append({"id": sample.name, "reason": "missing package"})
            continue

        destination = isolated_scene_root / sample.name
        shutil.copytree(
            sample,
            destination,
            ignore=shutil.ignore_patterns(*DERIVED_NAMES),
        )
        title = project.get("title") if isinstance(project.get("title"), str) else sample.name
        tree_hash, file_count, byte_count = tree_manifest(sample)
        sample_manifest = {
            "id": sample.name,
            "title": title,
            "package_file": package.name,
            "project_sha256": sha256(project_path),
            "package_sha256": sha256(package),
            "tree_sha256": tree_hash,
            "file_count": file_count,
            "byte_count": byte_count,
        }
        manifest_samples.append(sample_manifest)
        matrix_samples.append({
            "id": sample.name,
            "title": title,
            "project_sha256": sample_manifest["project_sha256"],
            "package_sha256": sample_manifest["package_sha256"],
            "expected_runtime_evidence_schema": args.runtime_evidence_schema,
        })

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
