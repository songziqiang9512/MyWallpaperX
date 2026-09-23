#!/usr/bin/env python3
"""Copy a bounded Scene benchmark evidence set into the local ignored cache."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import sys
from pathlib import Path
from typing import Any


SCRIPT_DIRECTORY = Path(__file__).resolve().parent
if str(SCRIPT_DIRECTORY) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIRECTORY))

from scene_capability_census_io import is_sample_directory_name


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
EVIDENCE_ROOT = REPOSITORY_ROOT / "docs/scene/evidence"
RUN_LABEL_PATTERN = re.compile(r"[a-z0-9][a-z0-9-]*")
DEFAULT_EVIDENCE_KEYS = (
    "app_log",
    "app_log_path",
    "preview_log",
    "runtime_evidence",
    "daemon_client_result_path",
    "ready_snapshot",
    "hover_snapshot",
    "pointer_trajectory_snapshots",
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
        sample_ids: set[str] = set()
        report_bytes = report_path.stat().st_size
        total_bytes += report_bytes
        for sample in samples:
            sample_id = str(sample.get("id", ""))
            evidence = sample.get("evidence")
            if (
                not is_sample_directory_name(sample_id)
                or not isinstance(evidence, dict)
            ):
                raise ValueError(f"report sample evidence is malformed: {report_path}")
            if sample_id in sample_ids:
                raise ValueError(
                    f"report has duplicate sample identity {sample_id}: {report_path}"
                )
            sample_ids.add(sample_id)
            seen_sources: set[Path] = set()
            for key in evidence_keys:
                raw_value = evidence.get(key)
                if key == "pointer_trajectory_snapshots":
                    if raw_value is None:
                        continue
                    if not isinstance(raw_value, list) or len(raw_value) not in (
                        0, 2, 3, 4, 5, 6, 7, 8
                    ):
                        raise ValueError(
                            f"pointer trajectory evidence is malformed: {report_path}"
                        )
                    if any(
                        not isinstance(raw_source, str) or not raw_source
                        for raw_source in raw_value
                    ):
                        raise ValueError(
                            f"pointer trajectory evidence is malformed: {report_path}"
                        )
                    sources = [
                        (f"pointer_trajectory_snapshot_{index:02d}", raw_source)
                        for index, raw_source in enumerate(raw_value)
                    ]
                elif isinstance(raw_value, str):
                    sources = [(key, raw_value)]
                else:
                    continue
                for archived_key, raw_source in sources:
                    source = evidence_source(report_path, raw_source)
                    if source in seen_sources:
                        continue
                    seen_sources.add(source)
                    suffix = "".join(source.suffixes)
                    relative = (
                        Path("samples") / sample_id / f"{archived_key}{suffix}"
                    )
                    files.append({
                        "key": archived_key,
                        "source": source,
                        "relative": relative,
                    })
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
                archived = (run_root / relative).resolve()
                try:
                    archived.relative_to(run_root.resolve())
                except ValueError as error:
                    raise ValueError(
                        f"archive path escapes run destination: {relative}"
                    ) from error
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
            "retention_class": "local-ignored-evidence-cache",
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
    print(f"Scene evidence cached locally: {destination}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
