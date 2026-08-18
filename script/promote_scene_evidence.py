#!/usr/bin/env python3
"""Promote a bounded Scene benchmark evidence set into the repository."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
from pathlib import Path
from typing import Any


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
EVIDENCE_ROOT = REPOSITORY_ROOT / "docs/scene/evidence"
RUN_LABEL_PATTERN = re.compile(r"[a-z0-9][a-z0-9-]*")
DEFAULT_EVIDENCE_KEYS = (
    "app_log",
    "preview_log",
    "runtime_evidence",
    "ready_snapshot",
    "after_snapshot",
)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def parse_run(value: str) -> tuple[str, Path]:
    label, separator, raw_path = value.partition("=")
    if not separator or RUN_LABEL_PATTERN.fullmatch(label) is None:
        raise argparse.ArgumentTypeError("run must use lowercase-label=/path/report.json")
    path = Path(raw_path).expanduser().resolve()
    if not path.is_file():
        raise argparse.ArgumentTypeError(f"run report does not exist: {path}")
    return label, path


def destination_path(relative: Path) -> Path:
    if relative.is_absolute() or relative == Path("."):
        raise ValueError("destination must be a non-empty path below docs/scene/evidence")
    destination = (EVIDENCE_ROOT / relative).resolve()
    try:
        destination.relative_to(EVIDENCE_ROOT.resolve())
    except ValueError as error:
        raise ValueError("destination escapes docs/scene/evidence") from error
    return destination


def evidence_source(report_path: Path, raw_path: str) -> Path:
    source = Path(raw_path).expanduser().resolve()
    try:
        source.relative_to(report_path.parent.resolve())
    except ValueError as error:
        raise ValueError(f"evidence path escapes benchmark output: {raw_path}") from error
    if not source.is_file():
        raise ValueError(f"evidence file is missing: {raw_path}")
    return source


def promotion_plan(
    runs: list[tuple[str, Path]],
    evidence_keys: tuple[str, ...] = DEFAULT_EVIDENCE_KEYS,
) -> tuple[list[dict[str, Any]], int]:
    labels: set[str] = set()
    planned_runs: list[dict[str, Any]] = []
    total_bytes = 0
    for label, report_path in runs:
        if label in labels:
            raise ValueError(f"duplicate run label: {label}")
        labels.add(label)
        report = json.loads(report_path.read_text(encoding="utf-8"))
        samples = report.get("samples")
        if not isinstance(samples, list) or not samples:
            raise ValueError(f"report has no samples: {report_path}")
        files: list[dict[str, Any]] = []
        report_bytes = report_path.stat().st_size
        total_bytes += report_bytes
        for sample in samples:
            sample_id = str(sample.get("id", ""))
            evidence = sample.get("evidence")
            if not sample_id or not isinstance(evidence, dict):
                raise ValueError(f"report sample evidence is malformed: {report_path}")
            for key in evidence_keys:
                raw_source = evidence.get(key)
                if not isinstance(raw_source, str):
                    continue
                source = evidence_source(report_path, raw_source)
                suffix = "".join(source.suffixes)
                relative = Path("samples") / sample_id / f"{key}{suffix}"
                files.append({"key": key, "source": source, "relative": relative})
                total_bytes += source.stat().st_size
        planned_runs.append({
            "label": label,
            "report": report_path,
            "files": files,
        })
    return planned_runs, total_bytes


def promote(
    runs: list[tuple[str, Path]],
    destination_relative: Path,
    max_package_mib: int,
) -> Path:
    destination = destination_path(destination_relative)
    if destination.exists():
        raise ValueError(f"evidence destination already exists: {destination}")
    planned_runs, total_bytes = promotion_plan(runs)
    maximum_bytes = max_package_mib * 1024 * 1024
    if total_bytes > maximum_bytes:
        raise ValueError(
            f"evidence package is {total_bytes} bytes, above {max_package_mib} MiB budget"
        )

    temporary = destination.with_name(f".{destination.name}.tmp-{os.getpid()}")
    if temporary.exists():
        raise ValueError(f"temporary evidence destination already exists: {temporary}")
    manifest_runs: list[dict[str, Any]] = []
    temporary.mkdir(parents=True)
    try:
        for planned in planned_runs:
            label = str(planned["label"])
            report_path = Path(planned["report"])
            run_root = temporary / label
            run_root.mkdir()
            archived_report = run_root / "report.json"
            shutil.copyfile(report_path, archived_report)
            archived_files: list[dict[str, Any]] = []
            for item in planned["files"]:
                source = Path(item["source"])
                relative = Path(item["relative"])
                archived = run_root / relative
                archived.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(source, archived)
                archived_files.append({
                    "key": item["key"],
                    "path": str(Path(label) / relative),
                    "sha256": sha256(archived),
                    "size_bytes": archived.stat().st_size,
                })
            manifest_runs.append({
                "label": label,
                "report_path": str(Path(label) / "report.json"),
                "report_sha256": sha256(archived_report),
                "report_size_bytes": archived_report.stat().st_size,
                "files": archived_files,
            })
        manifest = {
            "schema_version": 1,
            "retention_class": "repository-evidence",
            "excluded_classes": [
                "staged-app",
                "runtime-sample",
                "runtime-home",
                "runtime-cache",
                "workshop-package",
            ],
            "package_size_bytes": total_bytes,
            "runs": manifest_runs,
        }
        (temporary / "manifest.json").write_text(
            json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
        destination.parent.mkdir(parents=True, exist_ok=True)
        temporary.rename(destination)
    except BaseException:
        shutil.rmtree(temporary, ignore_errors=True)
        raise
    return destination


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--run",
        action="append",
        required=True,
        type=parse_run,
        help="lowercase-label=/absolute/path/to/report.json; may be repeated",
    )
    parser.add_argument(
        "--destination",
        required=True,
        type=Path,
        help="fresh path relative to docs/scene/evidence",
    )
    parser.add_argument("--max-package-mib", type=int, default=32)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.max_package_mib <= 0:
        print("Scene evidence promotion failed: package budget must be positive")
        return 2
    try:
        destination = promote(args.run, args.destination, args.max_package_mib)
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"Scene evidence promotion failed: {error}")
        return 2
    print(f"Scene evidence promoted: {destination}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
