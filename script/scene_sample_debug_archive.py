#!/usr/bin/env python3
"""Build a compact, traceable archive for a real Scene sample run.

The archive joins the read-only authored corpus census with one or more
``scene_wallpaper_benchmark`` reports and the existing first-breakpoint
normalizer.  It deliberately records structural runtime evidence only:
non-black output and a benchmark ``passed`` flag are not visual-correctness
claims.  Reports may cover a subset of the corpus; samples without a report
remain explicit ``not-run`` entries.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Mapping, Sequence

SCRIPT_PATH = Path(__file__).resolve()
SCRIPT_DIRECTORY = SCRIPT_PATH.parent
if str(SCRIPT_DIRECTORY) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIRECTORY))

from scene_capability_census_io import iter_sample_directories
from scene_diagnostic_report import (
    load_preview_oracle_registry,
    normalize_reports,
)


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SAMPLES_ROOT = Path.home() / "Movies/MyWallpaperX/创意工坊/Scene"
DEFAULT_SNAPSHOT = REPOSITORY_ROOT / ".artifacts/scene-evidence/census/scene_capability_census_snapshot.json"

CLAIM_BOUNDARY = (
    "runtime-first-breakpoint-and-lifecycle-diagnostics-only-not-visual-correctness"
)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _json(path: Path) -> tuple[Mapping[str, Any], str]:
    try:
        data = path.read_bytes()
        value = json.loads(data.decode("utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ValueError(f"cannot load JSON {path}: {error}") from error
    if not isinstance(value, Mapping):
        raise ValueError(f"JSON document is not an object: {path}")
    return value, hashlib.sha256(data).hexdigest()


def _corpus_manifest(sample_ids: Sequence[str]) -> str:
    payload = ("\n".join(sample_ids) + "\n").encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def _sample_status(observation: Mapping[str, Any] | None) -> str:
    if observation is None:
        return "not-run"
    status = observation.get("basicDisplayStatus")
    if status == "blocked":
        return "blocked"
    if status == "degraded":
        return "degraded-runtime"
    if status == "terminal-chain-complete":
        return "structural-chain-complete-visual-review"
    if status == "runtime-evidence-incomplete":
        return "runtime-evidence-incomplete"
    return "runtime-status-unknown"


def _next_action(status: str, first_breakpoint: Mapping[str, Any] | None) -> str:
    if status == "not-run":
        return "run-isolated-authored-sample"
    if status == "blocked":
        if first_breakpoint:
            stage = first_breakpoint.get("stage", "unknown-stage")
            owner = first_breakpoint.get("owner", "unknown-owner")
            reason = first_breakpoint.get("reasonCode", "unknown-reason")
            return f"repair-shared-owner:{stage}:{owner}:{reason}"
        return "locate-first-runtime-breakpoint"
    if status == "degraded-runtime":
        return "inspect-fallback-and-authored-visual-ROI"
    if status == "structural-chain-complete-visual-review":
        return "perform-authored-preview-and-next-frame-visual-review"
    return "add-or-reproduce-runtime-evidence"


def build_archive(
    samples_root: Path,
    snapshot_path: Path,
    report_paths: Sequence[Path],
    *,
    base_archive_path: Path | None = None,
) -> dict[str, Any]:
    if not snapshot_path.is_file():
        raise ValueError(
            f"census cache is missing: {snapshot_path}; pass --snapshot <existing-cache> "
            "or explicitly run python3.12 script/scene_capability_census.py generate "
            "with the matching --samples-root and --snapshot first"
        )
    if not samples_root.is_dir():
        raise ValueError(f"samples root is not a directory: {samples_root}")
    if not report_paths:
        raise ValueError("at least one benchmark report is required")

    sample_ids = [item.name for item in iter_sample_directories(samples_root)]
    if not sample_ids:
        raise ValueError(f"no samples found below {samples_root}")

    snapshot, snapshot_sha = _json(snapshot_path)
    static_rows = snapshot.get("samples")
    if not isinstance(static_rows, list):
        raise ValueError(f"census snapshot has no samples array: {snapshot_path}")
    static_by_id: dict[str, Mapping[str, Any]] = {}
    for row in static_rows:
        if not isinstance(row, Mapping) or not isinstance(row.get("sample_id"), str):
            raise ValueError(f"census snapshot has malformed sample row: {snapshot_path}")
        if row["sample_id"] in static_by_id:
            raise ValueError(f"duplicate census sample: {row['sample_id']}")
        static_by_id[row["sample_id"]] = row
    base: Mapping[str, Any] = {}
    retained: dict[str, dict[str, Any]] = {}
    base_source: dict[str, Any] = {}
    if base_archive_path is not None:
        base, base_sha = _json(base_archive_path)
        if (base.get("kind") != "scene-sample-debug-archive"
                or base.get("claimBoundary") != CLAIM_BOUNDARY
                or not isinstance(base.get("samples"), list)):
            raise ValueError(f"invalid base archive: {base_archive_path}")
        for row in base["samples"]:
            if not isinstance(row, dict) or not isinstance(row.get("id"), str):
                raise ValueError(f"malformed base archive sample: {base_archive_path}")
            if row["id"] in retained:
                raise ValueError(f"duplicate base archive sample: {row['id']}")
            retained[row["id"]] = row
        if set(retained) & set(static_by_id):
            raise ValueError("base archive and new census sample IDs overlap")
        if snapshot.get("snapshot", {}).get("inputs", {}).get("scope") != "subset":
            raise ValueError("base archive append requires an explicit subset census")
        base_source = {"baseArchive": {
            "path": str(base_archive_path), "sha256": base_sha,
            "sampleCount": len(retained),
        }}
    observed_ids = set(retained) | set(static_by_id)
    if observed_ids != set(sample_ids):
        missing = sorted(set(sample_ids) - observed_ids)
        extra = sorted(observed_ids - set(sample_ids))
        raise ValueError(
            f"census/sample-root mismatch: missing={missing[:5]} extra={extra[:5]}"
        )

    reports: list[Mapping[str, Any]] = []
    raw_by_id: dict[str, tuple[Path, str, int, Mapping[str, Any]]] = {}
    report_meta: list[dict[str, Any]] = []
    for report_path in report_paths:
        report, report_sha = _json(report_path)
        raw_samples = report.get("samples")
        if not isinstance(raw_samples, list):
            raise ValueError(f"benchmark report has no samples array: {report_path}")
        report_meta.append({
            "path": str(report_path),
            "sha256": report_sha,
            "matrix": report.get("matrix"),
            "matrixSha256": report.get("matrix_sha256"),
            "sampleCount": len(raw_samples),
        })
        reports.append(report)
        for index, sample in enumerate(raw_samples):
            if not isinstance(sample, Mapping) or not isinstance(sample.get("id"), str):
                raise ValueError(f"malformed sample in benchmark report: {report_path}")
            sample_id = sample["id"]
            if base_archive_path is not None and sample_id not in static_by_id:
                raise ValueError(f"new report sample is outside the subset census: {sample_id}")
            if sample_id in raw_by_id:
                raise ValueError(f"duplicate sample id across reports: {sample_id}")
            raw_by_id[sample_id] = (report_path, report_sha, index, sample)

    preview_oracle_registry_path = (
        Path(__file__).resolve().parent
        / "scene_sample_preview_oracle_registry.json"
    )
    preview_oracle_uncontrolled = load_preview_oracle_registry(
        preview_oracle_registry_path
    )
    normalized = normalize_reports(reports, preview_oracle_uncontrolled)
    observations = {
        str(item["sampleId"]): item
        for item in normalized.get("samples", [])
        if isinstance(item, Mapping) and isinstance(item.get("sampleId"), str)
    }

    archive_samples: list[dict[str, Any]] = []
    for sample_id in sample_ids:
        if sample_id in retained:
            archive_samples.append(retained[sample_id])
            continue
        row = static_by_id[sample_id]
        observation = observations.get(sample_id)
        status = _sample_status(observation)
        first = observation.get("firstBreakpoint") if observation else None
        if not isinstance(first, Mapping):
            first = None

        runtime: dict[str, Any] = {
            "status": status,
            "firstBreakpoint": first,
        }
        if observation:
            runtime["secondaryEvents"] = observation.get("secondaryEvents", [])
            runtime["evidenceSummary"] = observation.get("evidenceSummary", {})
            runtime["benchmarkResultIgnored"] = observation.get(
                "benchmarkResultIgnored", {}
            )

        evidence: dict[str, Any] = {"report": None}
        raw_info = raw_by_id.get(sample_id)
        if raw_info:
            report_path, report_sha, report_index, raw_sample = raw_info
            raw_evidence = raw_sample.get("evidence")
            paths = {
                str(key): value
                for key, value in raw_evidence.items()
                if isinstance(value, str)
            } if isinstance(raw_evidence, Mapping) else {}
            evidence = {
                "report": {
                    "path": str(report_path),
                    "sha256": report_sha,
                    "sampleIndex": report_index,
                },
                "sampleEvidencePaths": paths,
            }

        archive_samples.append({
            "id": sample_id,
            "title": row.get("title", sample_id),
            "authored": {
                "projectSha256": row.get("project_sha256"),
                "packageSha256": row.get("package_sha256"),
                "parseState": row.get("parse_state"),
                "objectCount": row.get("object_count"),
                "occurrenceCount": row.get("occurrence_count"),
                "visibleOccurrenceCount": row.get("visible_occurrence_count"),
                "effectInstanceCount": row.get("effect_instance_count"),
                "particleLayerCount": row.get("particle_layer_count"),
                "dynamicFeatureCounts": row.get("dynamic_feature_counts", {}),
            },
            "runtime": runtime,
            "evidence": evidence,
            "nextAction": _next_action(status, first),
        })

    status_counts: Counter[str] = Counter()
    breakpoint_counts: Counter[str] = Counter()
    for row in archive_samples:
        status_counts[row["runtime"]["status"]] += 1
        first = row["runtime"].get("firstBreakpoint")
        if first:
            key = f"{first.get('stage', 'unknown-stage')}:{first.get('reasonCode', 'unknown-reason')}"
            breakpoint_counts[key] += 1
    app_identities = list(base.get("appIdentities", []))
    app_identities.extend(
        report.get("app_identity")
        for report in reports
        if isinstance(report.get("app_identity"), Mapping)
    )
    return {
        "schemaVersion": 1,
        "kind": "scene-sample-debug-archive",
        "claimBoundary": CLAIM_BOUNDARY,
        "generatedAtUtc": datetime.now(timezone.utc).isoformat(),
        "source": {
            **base_source,
            "samplesRoot": str(samples_root),
            "sampleCount": len(sample_ids),
            "sampleIdManifestSha256": _corpus_manifest(sample_ids),
            "censusSnapshot": {
                "path": str(snapshot_path),
                "sha256": snapshot_sha,
                "sampleCount": len(static_rows),
                **({"scope": "subset"} if base_archive_path is not None else {}),
            },
            "previewOracleRegistry": {
                "path": str(preview_oracle_registry_path),
                "sha256": sha256_file(preview_oracle_registry_path),
                "registeredSampleCount": len(preview_oracle_uncontrolled),
            },
        },
        "reports": [*base.get("reports", []), *report_meta],
        "appIdentities": app_identities,
        "summary": {
            "sampleCount": len(archive_samples),
            "reportedSampleCount": sum(row["evidence"].get("report") is not None for row in archive_samples),
            "statusCounts": dict(sorted(status_counts.items())),
            "firstBreakpointCounts": dict(sorted(breakpoint_counts.items())),
            "normalizedDiagnosticClaim": normalized.get("claimBoundary"),
        },
        "samples": archive_samples,
    }


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--samples-root", type=Path, default=DEFAULT_SAMPLES_ROOT)
    parser.add_argument("--snapshot", type=Path, default=DEFAULT_SNAPSHOT)
    parser.add_argument("--base-archive", type=Path)
    parser.add_argument("--report", type=Path, action="append", required=True)
    parser.add_argument("--output", type=Path, required=True)
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    try:
        archive = build_archive(
            args.samples_root.expanduser().resolve(),
            args.snapshot.expanduser().resolve(),
            [path.expanduser().resolve() for path in args.report],
            base_archive_path=args.base_archive.expanduser().resolve() if args.base_archive else None,
        )
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(
            json.dumps(archive, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
    except (OSError, ValueError) as error:
        print(f"scene_sample_debug_archive: {error}", file=sys.stderr)
        return 2
    print(json.dumps({
        "sampleCount": archive["summary"]["sampleCount"],
        "reportedSampleCount": archive["summary"]["reportedSampleCount"],
        "statusCounts": archive["summary"]["statusCounts"],
        "output": str(args.output),
    }, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
