"""Contracts for the Scene product-entry audio corpus baseline.

This module is intentionally not a second command-line tool. The existing
``scene_wallpaper_benchmark.py`` owns staging, execution, cleanup, and report
publication; these helpers only keep the audio-corpus source and S3 result
classification out of that already-large driver.
"""

from __future__ import annotations

import json
import math
from collections import Counter
from pathlib import Path
from typing import Any


PRODUCT_ENTRY_AUDIO_MODE = "product-entry-audio-baseline"
PRODUCT_ENTRY_RECORD_ID = "debug-scene-daemon-client"
PRIVATE_DEFAULTS_PREFIX = "com.songziqiang.MyWallpaperX.Debug.AudioCorpus."


def load_audio_declaration_matrix(snapshot_path: Path) -> dict[str, Any]:
    payload = json.loads(snapshot_path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise ValueError("Scene capability snapshot must be an object")
    summary = payload.get("summary")
    audio = summary.get("audio_declarations") if isinstance(summary, dict) else None
    if not isinstance(audio, dict):
        raise ValueError("Scene capability snapshot has no audio declaration summary")
    sample_ids = audio.get("relationship_sample_ids")
    expected_count = audio.get("relationship_sample_count")
    if (
        not isinstance(sample_ids, list)
        or not sample_ids
        or any(
            not isinstance(value, str)
            or not value.isascii()
            or not value.isdigit()
            for value in sample_ids
        )
        or len(sample_ids) != len(set(sample_ids))
        or sample_ids != sorted(sample_ids)
        or isinstance(expected_count, bool)
        or not isinstance(expected_count, int)
        or expected_count != len(sample_ids)
    ):
        raise ValueError("Scene audio declaration sample identity is not conserved")
    return {
        "schema_version": 1,
        "name": "scene-audio-declaration-product-entry-baseline",
        "samples": [{"id": sample_id} for sample_id in sample_ids],
        "source": {
            "kind": "scene-capability-census-snapshot",
            "relationship_sample_count": expected_count,
            "declaration_occurrence_count": audio.get(
                "declaration_occurrence_count"
            ),
        },
    }


def private_defaults_suite(sample_id: str) -> str:
    if not sample_id.isascii() or not sample_id.isdigit():
        raise ValueError("product-entry audio sample ID must contain ASCII digits")
    return PRIVATE_DEFAULTS_PREFIX + sample_id


def product_entry_command(
    runtime_binary: Path,
    runtime_sample: Path,
    result_dir: Path,
    runtime_workshop: Path,
    sample_id: str,
    duration: float,
) -> list[str]:
    return [
        str(runtime_binary),
        "--mwx-debug-scene-daemon-client",
        "--mwx-debug-scene-product-entry",
        "--mwx-debug-scene-daemon-stable",
        "--mwx-debug-scene-root",
        str(runtime_sample),
        "--mwx-debug-scene-evidence-dir",
        str(result_dir),
        "--mwx-debug-scene-duration",
        str(duration),
        "--mwx-debug-workshop-root",
        str(runtime_workshop),
        "--mwx-debug-user-defaults-suite",
        private_defaults_suite(sample_id),
    ]


def classify_product_entry_result(
    sample_id: str,
    payload: Any,
    *,
    exit_code: int,
    timed_out: bool,
) -> dict[str, Any]:
    failures: list[str] = []
    process_failed = False
    if timed_out:
        failures.append("product-entry process timed out")
        process_failed = True
    if exit_code != 0:
        failures.append(f"product-entry process exited with status {exit_code}")
        process_failed = True
    if not isinstance(payload, dict):
        return {
            "status": (
                "process-execution-failure" if process_failed else "result-missing"
            ),
            "passed": False,
            "failures": failures + ["daemon client result is missing or malformed"],
            "evidence_ceiling": "S0-no-executable-result",
        }

    runner_failures = payload.get("failures")
    runner_failed = False
    if not isinstance(runner_failures, list) or any(
        not isinstance(value, str) for value in runner_failures
    ):
        failures.append("daemon client failures field is malformed")
        runner_failures = []
        runner_failed = True
    elif runner_failures:
        runner_failed = True
    failures.extend(f"daemon-client:{value}" for value in runner_failures)

    identity_failed = False
    if payload.get("sampleID") != sample_id:
        failures.append("daemon client sample identity mismatch")
        identity_failed = True
    if payload.get("launchEntry") != "steam-workshop-product":
        failures.append("product entry identity missing")
        identity_failed = True
    if payload.get("stableDaemonClientRequested") is not True:
        failures.append("stable daemon client mode missing")
        identity_failed = True

    first_present_count = _nonnegative_integer(payload.get("firstPresentCount"))
    first_present_record_ids = payload.get("firstPresentRecordIDs")
    unique_request_count = _nonnegative_integer(payload.get("uniqueRequestCount"))
    publication_count = _nonnegative_integer(
        payload.get("audioSpectrumPublicationCount")
    )
    scope_epoch = _nonnegative_integer(payload.get("audioSpectrumScopeEpoch"))
    peaks = payload.get("audioSpectrumPublicationPeaks")
    positive_peaks = [
        float(value)
        for value in peaks
        if type(value) in (int, float)
        and math.isfinite(float(value))
        and float(value) > 0
    ] if isinstance(peaks, list) else []
    latest_stats = payload.get("latestStats")
    rendered = (
        _nonnegative_integer(latest_stats.get("rendered"))
        if isinstance(latest_stats, dict)
        else None
    )

    if process_failed:
        status = "process-execution-failure"
    elif runner_failed:
        status = "daemon-client-failure"
    elif identity_failed:
        status = "result-identity-invalid"
    elif payload.get("launchPhase") != "launched":
        status = "launch-not-complete"
        failures.append("product Scene launch did not reach launched")
    elif payload.get("activeRecordID") != PRODUCT_ENTRY_RECORD_ID:
        status = "record-identity-mismatch"
        failures.append("active product record identity mismatch")
    elif first_present_count is None or first_present_count < 1:
        status = "first-present-missing"
        failures.append("product Scene first-present is missing")
    elif (
        first_present_count != 1
        or first_present_record_ids != [PRODUCT_ENTRY_RECORD_ID]
    ):
        status = "first-present-identity-invalid"
        failures.append("product Scene first-present identity is not exact-once")
    elif unique_request_count != 1:
        status = "request-identity-invalid"
        failures.append("product Scene request identity is not unique")
    elif payload.get("audioSpectrumDemanded") is not True or not scope_epoch:
        status = "audio-demand-missing"
        failures.append("product Scene audio demand is missing")
    elif publication_count is None or publication_count < 1 or not positive_peaks:
        status = "nonzero-publication-missing"
        failures.append("product Scene nonzero audio publication is missing")
    elif publication_count != len(peaks) or publication_count != len(positive_peaks):
        status = "publication-evidence-malformed"
        failures.append("audio publication count does not match peak evidence")
    elif rendered is None or rendered < 1:
        status = "rendered-frame-missing"
        failures.append("product Scene rendered frame evidence is missing")
    elif failures:
        status = "runtime-failure"
    else:
        status = "capture-publication-observed"

    return {
        "status": status,
        "passed": not failures,
        "failures": failures,
        "evidence_ceiling": "S3-capture-publication",
        "visual_validated": False,
        "consumer_execution_validated": False,
        "first_present_count": first_present_count,
        "unique_request_count": unique_request_count,
        "audio_demanded": payload.get("audioSpectrumDemanded") is True,
        "audio_scope_epoch": scope_epoch,
        "nonzero_publication_count": len(positive_peaks),
        "maximum_publication_peak": max(positive_peaks, default=None),
        "rendered_frames": rendered,
    }


def summarize_product_entry_results(
    results: list[dict[str, Any]],
) -> dict[str, Any]:
    status_counts = Counter(str(result["baseline"]["status"]) for result in results)
    sample_ids_by_status = {
        status: sorted(
            str(result["id"])
            for result in results
            if result["baseline"]["status"] == status
        )
        for status in sorted(status_counts)
    }
    passed_ids = sample_ids_by_status.get("capture-publication-observed", [])
    return {
        "passed": len(passed_ids) == len(results),
        "sample_count": len(results),
        "passed_count": len(passed_ids),
        "status_counts": dict(sorted(status_counts.items())),
        "sample_ids_by_status": sample_ids_by_status,
        "evidence_ceiling": "S3-capture-publication",
        "visual_validated_count": 0,
        "consumer_execution_validated_count": 0,
    }


def _nonnegative_integer(value: Any) -> int | None:
    if isinstance(value, bool) or not isinstance(value, int) or value < 0:
        return None
    return value
