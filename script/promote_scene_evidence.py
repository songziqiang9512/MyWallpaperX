#!/usr/bin/env python3
"""Copy a bounded Scene benchmark evidence set into the local ignored cache."""

from __future__ import annotations

import argparse
from contextlib import contextmanager
import fcntl
import hashlib
import json
import os
import re
import shutil
import subprocess
import time
import sys
from pathlib import Path
from typing import Any


SCRIPT_DIRECTORY = Path(__file__).resolve().parent
if str(SCRIPT_DIRECTORY) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIRECTORY))

from scene_capability_census_io import is_sample_directory_name


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
EVIDENCE_ROOT = REPOSITORY_ROOT / ".artifacts/scene-evidence/runs"
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


def checked_evidence_root() -> Path:
    root = EVIDENCE_ROOT.absolute()
    for part in (root, *root.parents):
        if part.is_symlink():
            raise ValueError(f'evidence root has a symlink ancestor: {part}')
    return root


def destination_path(relative: Path) -> Path:
    if relative.is_absolute() or relative == Path(".") or ".." in relative.parts:
        raise ValueError("destination must be a non-empty path below .artifacts/scene-evidence/runs")
    root = checked_evidence_root()
    lexical = root / relative
    for part in (lexical, *lexical.parents):
        if part == root:
            break
        if part.is_symlink():
            raise ValueError('evidence destination has a symlink ancestor')
    destination = lexical.resolve()
    try:
        destination.relative_to(EVIDENCE_ROOT.resolve())
    except ValueError as error:
        raise ValueError("destination escapes .artifacts/scene-evidence/runs") from error
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


@contextmanager
def evidence_lock():
    root = checked_evidence_root()
    root.parent.mkdir(parents=True, exist_ok=True)
    lock = root.parent / '.evidence-retention.lock'
    descriptor = os.open(lock, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    try:
        fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
        yield
    finally:
        os.close(descriptor)


def prune_expired(now: float | None = None) -> dict:
    try:
        with evidence_lock():
            return _prune_expired(now)
    except (OSError, ValueError) as error:
        return {'removed': [], 'retained': [{'path': str(EVIDENCE_ROOT), 'reason': str(error)}]}


def promote(runs, destination_relative, max_package_mib, retain_days=14,
            max_cache_mib=1024, protect_reason='') -> Path:
    with evidence_lock():
        return _promote(runs, destination_relative, max_package_mib, retain_days,
                        max_cache_mib, protect_reason)


def _prune_expired(now: float | None = None) -> dict:
    """Delete only expired, unchanged packages created by this producer."""
    now = time.time() if now is None else now
    removed, retained = [], []
    try:
        checked_evidence_root()
    except ValueError as error:
        return {'removed': [], 'retained': [{'path': str(EVIDENCE_ROOT), 'reason': str(error)}]}
    if not EVIDENCE_ROOT.exists():
        return {'removed': removed, 'retained': retained}
    for manifest_path in sorted(EVIDENCE_ROOT.rglob('manifest.json')):
        package = manifest_path.parent
        try:
            if package == EVIDENCE_ROOT or package.resolve() == EVIDENCE_ROOT.resolve():
                raise ValueError('cache root is not a removable package')
            if (not package.resolve().is_relative_to(EVIDENCE_ROOT.resolve())
                    or package.is_symlink() or any(p.is_symlink() for p in package.rglob('*'))):
                raise ValueError('symlink')
            manifest = json.loads(manifest_path.read_text())
            if not isinstance(manifest, dict):
                raise ValueError('unrecognized manifest: expected an object; evidence preserved')
            expiry = manifest.get('expires_at')
            if (manifest.get('producer') != 'promote_scene_evidence'
                    or type(expiry) not in (int, float) or not 0 < expiry <= now):
                continue
            expected = {'manifest.json'}
            for run in manifest['runs']:
                items = [(run['report_path'], run['report_sha256'])]
                items.extend((item['path'], item['sha256']) for item in run['files'])
                for relative, digest in items:
                    file = package / relative
                    if not file.resolve().is_relative_to(package.resolve()) or not file.is_file():
                        raise ValueError('missing or escaped file')
                    if sha256(file) != digest:
                        raise ValueError('changed evidence')
                    expected.add(relative)
            actual = {p.relative_to(package).as_posix() for p in package.rglob('*') if p.is_file()}
            if actual != expected:
                raise ValueError('unregistered evidence')
            opened = subprocess.run(['/usr/sbin/lsof', '-t', '+D', str(package)],
                                    capture_output=True, timeout=20)
            if opened.returncode != 1 or opened.stdout or opened.stderr:
                raise ValueError('open files or unavailable writer check')
            shutil.rmtree(package)
            removed.append(str(package.resolve()))
        except (OSError, ValueError, KeyError, TypeError, subprocess.TimeoutExpired) as error:
            retained.append({'path': str(package), 'reason': str(error)})
    return {'removed': removed, 'retained': retained}


def _promote(
    runs: list[tuple[str, Path]],
    destination_relative: Path,
    max_package_mib: int,
    retain_days: int = 14,
    max_cache_mib: int = 1024,
    protect_reason: str = "",
) -> Path:
    if not 1 <= retain_days <= 90 or max_cache_mib <= 0 or max_package_mib <= 0:
        raise ValueError('retention must be 1–90 days and budgets must be positive')
    destination = destination_path(destination_relative)
    if destination.exists():
        raise ValueError(f"evidence destination already exists: {destination}")
    planned_runs, total_bytes = promotion_plan(runs)
    maximum_bytes = max_package_mib * 1024 * 1024
    if total_bytes > maximum_bytes:
        raise ValueError(
            f"evidence package is {total_bytes} bytes, above {max_package_mib} MiB budget"
        )

    current_bytes = sum(p.stat().st_size for p in EVIDENCE_ROOT.rglob('*')
                        if p.is_file() and not p.is_symlink()) if EVIDENCE_ROOT.exists() else 0
    if current_bytes + total_bytes > max_cache_mib * 1024 * 1024:
        raise ValueError('evidence cache budget exceeded; run --prune-expired or review retained packages')
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
            "producer": "promote_scene_evidence",
            "created_at": time.time(),
            "expires_at": None if protect_reason else time.time() + retain_days * 86400,
            "protect_reason": protect_reason,
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
        actual_bytes = sum(p.stat().st_size for p in temporary.rglob('*') if p.is_file())
        if actual_bytes > maximum_bytes or current_bytes + actual_bytes > max_cache_mib * 1024 * 1024:
            raise ValueError('copied evidence including manifest exceeds package or cache budget')
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination_path(destination_relative)  # Recheck before publishing.
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
        default=[],
        type=parse_run,
        help="lowercase-label=/absolute/path/to/report.json; may be repeated",
    )
    parser.add_argument(
        "--destination",
        type=Path,
        help="fresh path relative to .artifacts/scene-evidence/runs",
    )
    parser.add_argument("--max-package-mib", type=int, default=32)
    parser.add_argument('--protect-reason', default='', help='preserve an unresolved failure; still counts against total cache budget')
    parser.add_argument('--retain-days', type=int, default=14)
    parser.add_argument('--max-cache-mib', type=int, default=1024)
    parser.add_argument('--prune-expired', action='store_true', help='remove unchanged expired packages; preserve unknown or active evidence')
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.prune_expired:
        print(json.dumps(prune_expired(), ensure_ascii=False, indent=2))
        if not args.run:
            return 0
    if not args.run or args.destination is None:
        print('Promotion requires --run and --destination')
        return 2
    if args.max_package_mib <= 0:
        print("Scene evidence promotion failed: package budget must be positive")
        return 2
    try:
        destination = promote(args.run, args.destination, args.max_package_mib, args.retain_days, args.max_cache_mib, args.protect_reason)
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"Scene evidence promotion failed: {error}")
        return 2
    print(f"Scene evidence cached locally: {destination}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
