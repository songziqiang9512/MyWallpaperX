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

from scene_capability_census_io import iter_numeric_sample_directories
from scene_diagnostic_report import normalize_reports


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SAMPLES_ROOT = Path.home() / "Movies/MyWallpaperX/创意工坊/Scene"
DEFAULT_SNAPSHOT = REPOSITORY_ROOT / "script/scene_capability_census_snapshot.json"

CLAIM_BOUNDARY = (
    "runtime-first-breakpoint-and-lifecycle-diagnostics-only-not-visual-correctness"
)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _json(path: Path) -> Mapping[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ValueError(f"cannot load JSON {path}: {error}") from error
    if not isinstance(value, Mapping):
        raise ValueError(f"JSON document is not an object: {path}")
    return value


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
) -> dict[str, Any]:
    if not samples_root.is_dir():
        raise ValueError(f"samples root is not a directory: {samples_root}")
    if not report_paths:
        raise ValueError("at least one benchmark report is required")

    sample_ids = [item.name for item in iter_numeric_sample_directories(samples_root)]
    if not sample_ids:
        raise ValueError(f"no numeric samples found below {samples_root}")

    snapshot = _json(snapshot_path)
    static_rows = snapshot.get("samples")
    if not isinstance(static_rows, list):
        raise ValueError(f"census snapshot has no samples array: {snapshot_path}")
    static_by_id: dict[str, Mapping[str, Any]] = {}
    for row in static_rows:
        if not isinstance(row, Mapping) or not isinstance(row.get("sample_id"), str):
            raise ValueError(f"census snapshot has malformed sample row: {snapshot_path}")
        static_by_id[row["sample_id"]] = row
    if set(static_by_id) != set(sample_ids):
        missing = sorted(set(sample_ids) - set(static_by_id))
        extra = sorted(set(static_by_id) - set(sample_ids))
        raise ValueError(
            f"census/sample-root mismatch: missing={missing[:5]} extra={extra[:5]}"
        )

    reports: list[Mapping[str, Any]] = []
    raw_by_id: dict[str, tuple[Path, str, int, Mapping[str, Any]]] = {}
    report_meta: list[dict[str, Any]] = []
    for report_path in report_paths:
        report = _json(report_path)
        raw_samples = report.get("samples")
        if not isinstance(raw_samples, list):
            raise ValueError(f"benchmark report has no samples array: {report_path}")
        report_sha = sha256_file(report_path)
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
            if sample_id in raw_by_id:
                raise ValueError(f"duplicate sample id across reports: {sample_id}")
            raw_by_id[sample_id] = (report_path, report_sha, index, sample)

    normalized = normalize_reports(reports)
    observations = {
        str(item["sampleId"]): item
        for item in normalized.get("samples", [])
        if isinstance(item, Mapping) and isinstance(item.get("sampleId"), str)
    }

    archive_samples: list[dict[str, Any]] = []
    status_counts: Counter[str] = Counter()
    breakpoint_counts: Counter[str] = Counter()
    for sample_id in sample_ids:
        row = static_by_id[sample_id]
        observation = observations.get(sample_id)
        status = _sample_status(observation)
        first = observation.get("firstBreakpoint") if observation else None
        if not isinstance(first, Mapping):
            first = None
        status_counts[status] += 1
        if first:
            key = f"{first.get('stage', 'unknown-stage')}:{first.get('reasonCode', 'unknown-reason')}"
            breakpoint_counts[key] += 1

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

    app_identities = [
        report.get("app_identity")
        for report in reports
        if isinstance(report.get("app_identity"), Mapping)
    ]
    return {
        "schemaVersion": 1,
        "kind": "scene-sample-debug-archive",
        "claimBoundary": CLAIM_BOUNDARY,
        "generatedAtUtc": datetime.now(timezone.utc).isoformat(),
        "source": {
            "samplesRoot": str(samples_root),
            "sampleCount": len(sample_ids),
            "sampleIdManifestSha256": _corpus_manifest(sample_ids),
            "censusSnapshot": {
                "path": str(snapshot_path),
                "sha256": sha256_file(snapshot_path),
                "sampleCount": len(static_rows),
            },
        },
        "reports": report_meta,
        "appIdentities": app_identities,
        "summary": {
            "sampleCount": len(archive_samples),
            "reportedSampleCount": len(raw_by_id),
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
