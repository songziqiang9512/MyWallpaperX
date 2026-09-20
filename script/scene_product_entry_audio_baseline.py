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


def parse_product_entry_property_overrides(
    raw_payload: str | None,
) -> dict[str, str | float | bool]:
    if raw_payload is None:
        return {}
    try:
        raw_payload_size = len(raw_payload.encode("utf-8"))
    except UnicodeEncodeError as error:
        raise ValueError(
            "product-entry property override payload must be valid UTF-8"
        ) from error
    if raw_payload_size > 65_536:
        raise ValueError("product-entry property override payload is too large")

    def unique_object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
        result: dict[str, Any] = {}
        for key, value in pairs:
            if key in result:
                raise ValueError(
                    f"duplicate product-entry property override key: {key}"
                )
            result[key] = value
        return result

    def reject_constant(value: str) -> Any:
        raise ValueError(f"invalid product-entry property number: {value}")

    try:
        payload = json.loads(
            raw_payload,
            object_pairs_hook=unique_object,
            parse_constant=reject_constant,
        )
    except (json.JSONDecodeError, RecursionError) as error:
        raise ValueError(
            "product-entry property overrides must be valid JSON"
        ) from error
    if not isinstance(payload, dict) or not 1 <= len(payload) <= 64:
        raise ValueError(
            "product-entry property overrides must contain 1...64 entries"
        )

    normalized: dict[str, str | float | bool] = {}
    for key, value in payload.items():
        try:
            key_size = len(key.encode("utf-8")) if isinstance(key, str) else 0
        except UnicodeEncodeError as error:
            raise ValueError(
                "invalid product-entry property override key"
            ) from error
        if (
            not isinstance(key, str)
            or not key
            or key_size > 512
            or any(ord(character) < 32 or ord(character) == 127 for character in key)
        ):
            raise ValueError("invalid product-entry property override key")
        if isinstance(value, bool):
            normalized[key] = value
        elif type(value) in (int, float):
            try:
                number = float(value)
            except (OverflowError, ValueError) as error:
                raise ValueError(
                    "product-entry property override must be finite"
                ) from error
            if not math.isfinite(number):
                raise ValueError("product-entry property override must be finite")
            normalized[key] = number
        elif isinstance(value, str):
            try:
                value_size = len(value.encode("utf-8"))
            except UnicodeEncodeError as error:
                raise ValueError(
                    "invalid product-entry property override string"
                ) from error
            if value_size > 16_384:
                raise ValueError(
                    "invalid product-entry property override string"
                )
            normalized[key] = value
        else:
            raise ValueError(
                "product-entry property override values must be string, number, or bool"
            )
    return dict(sorted(normalized.items()))


def typed_property_overrides_match(
    actual: Any,
    expected: dict[str, str | float | bool],
) -> bool:
    if not isinstance(actual, dict) or set(actual) != set(expected):
        return False
    for key, expected_value in expected.items():
        actual_value = actual[key]
        if isinstance(expected_value, bool):
            if type(actual_value) is not bool or actual_value is not expected_value:
                return False
        elif isinstance(expected_value, str):
            if type(actual_value) is not str or actual_value != expected_value:
                return False
        elif type(expected_value) in (int, float):
            if type(actual_value) not in (int, float):
                return False
            try:
                actual_number = float(actual_value)
            except (OverflowError, ValueError):
                return False
            if not math.isfinite(actual_number) or actual_number != float(expected_value):
                return False
        else:
            return False
    return True


def product_entry_command(
    runtime_binary: Path,
    runtime_sample: Path,
    result_dir: Path,
    runtime_workshop: Path,
    sample_id: str,
    duration: float,
    property_overrides: dict[str, str | float | bool] | None = None,
) -> list[str]:
    command = [
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
    if property_overrides:
        command.extend([
            "--mwx-debug-scene-properties-json",
            json.dumps(
                property_overrides,
                ensure_ascii=False,
                separators=(",", ":"),
                sort_keys=True,
            ),
        ])
    return command


def classify_product_entry_result(
    sample_id: str,
    payload: Any,
    *,
    exit_code: int,
    timed_out: bool,
    expected_property_overrides: dict[str, str | float | bool] | None = None,
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
    if expected_property_overrides is not None and not typed_property_overrides_match(
        payload.get("startupPropertyOverrides"),
        expected_property_overrides,
    ):
        failures.append("product-entry property override identity mismatch")
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
        "startup_property_overrides": payload.get("startupPropertyOverrides"),
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
