"""Build live input arguments and parse typed property update evidence."""

from __future__ import annotations

import json
import math
import re
from pathlib import Path
from typing import Any


LIVE_PROPERTY_UPDATE_RE = re.compile(
    r"phase=live-property-update accepted=(?P<accepted>true|false) "
    r"surfacesBefore=(?P<before>\d+) surfacesAfter=(?P<after>\d+) "
    r"windowsBefore=(?P<windows_before>[\d,]*) windowsAfter=(?P<windows_after>[\d,]*) "
    r"keys=(?P<keys>[^\n]*)"
)

DEFERRED_PROPERTY_TRANSITION_RE = re.compile(
    r"MWX deferred property transition: "
    r"schema=deferred-property-transition-v1 "
    r"generation=(?P<generation>\d+) "
    r"layers=(?P<layers>\d+(?:,\d+)*) "
    r"state=(?P<state>pending|committed|superseded|"
    r"failed:[A-Za-z0-9._-]+|cancelled:[A-Za-z0-9._-]+)(?=\s|$)"
)

DEFERRED_BASE_IMAGE_RE = re.compile(
    r"MWX deferred base image: schema=deferred-base-image-v2 "
    r"sceneGeneration=(?P<scene_generation>\d+) "
    r"requestGeneration=(?P<request_generation>\d+) "
    r"layer=(?P<layer>\d+) "
    r"status=(?P<status>ready|failed:[A-Za-z0-9._-]+)(?=\s|$)"
)

def append_property_arguments(
    command: list[str],
    property_overrides: Any,
    live_property_overrides: Any,
) -> None:
    arguments = [
        (property_overrides, "--mwx-debug-scene-properties-json"),
        (live_property_overrides, "--mwx-debug-scene-live-properties-json"),
    ]
    for values, flag in arguments:
        if isinstance(values, dict) and values:
            command.extend([
                flag,
                json.dumps(values, ensure_ascii=False, separators=(",", ":")),
            ])

def append_texture_override_argument(
    command: list[str],
    overrides: Any,
    runtime_sample: Path,
    failures: list[str],
) -> None:
    if overrides is None:
        return
    if not isinstance(overrides, dict) or not 1 <= len(overrides) <= 64:
        failures.append("invalid isolated user texture overrides")
        return
    root = runtime_sample.resolve()
    normalized: dict[str, str] = {}
    for key, raw_path in overrides.items():
        path = Path(raw_path) if isinstance(raw_path, str) else Path()
        target = (runtime_sample / path).resolve()
        if (
            not isinstance(key, str)
            or not key.strip()
            or any(ord(character) < 32 or ord(character) == 127 for character in key)
            or not isinstance(raw_path, str)
            or path.is_absolute()
            or ".." in path.parts
            or path.suffix.lower() not in {".png", ".jpg", ".jpeg"}
            or not target.is_relative_to(root)
            or not target.is_file()
        ):
            failures.append("invalid isolated user texture overrides")
            return
        normalized[key] = str(path)
    command.extend([
        "--mwx-debug-scene-textures-json",
        json.dumps(normalized, ensure_ascii=False, separators=(",", ":")),
    ])

def append_dynamic_values_fault_argument(
    command: list[str],
    frame_index: int | None,
) -> None:
    if frame_index is not None:
        command.extend([
            "--mwx-debug-scene-drop-dynamic-values-frame",
            str(frame_index),
        ])

def append_performance_profile_argument(
    command: list[str],
    frames_per_second: int,
) -> None:
    if frames_per_second not in (30, 60):
        raise ValueError("performance profile must be 30 or 60 FPS")
    command.extend([
        "--mwx-debug-scene-performance-fps",
        str(frames_per_second),
    ])

def append_performance_warmup_argument(
    command: list[str],
    warmup_seconds: float | None,
) -> None:
    if warmup_seconds is None:
        return
    if not math.isfinite(warmup_seconds) or warmup_seconds < 0:
        raise ValueError("performance warmup must be finite and nonnegative")
    command.extend([
        "--mwx-debug-scene-performance-warmup",
        str(warmup_seconds),
    ])

def append_resize_sequence_argument(
    command: list[str],
    resize_sequence: str | None,
) -> None:
    if resize_sequence is not None:
        command.extend([
            "--mwx-debug-scene-resize-sequence",
            resize_sequence,
        ])

def append_media_thumbnail_sequence_argument(
    command: list[str],
    sequence: Any,
    runtime_sample: Path,
    failures: list[str],
) -> None:
    if sequence is None:
        return
    if not isinstance(sequence, list) or not 1 <= len(sequence) <= 8:
        failures.append("invalid isolated media thumbnail sequence")
        return
    normalized: list[dict[str, Any]] = []
    for entry in sequence:
        if not isinstance(entry, dict):
            failures.append("invalid isolated media thumbnail sequence")
            return
        keys = set(entry)
        if keys not in ({"path", "delay"}, {"clear", "delay"}):
            failures.append("invalid isolated media thumbnail sequence")
            return
        delay = entry["delay"]
        if (
            isinstance(delay, bool)
            or not isinstance(delay, (int, float))
            or not math.isfinite(delay)
            or not 0.1 <= delay <= 60
        ):
            failures.append("invalid isolated media thumbnail sequence")
            return
        if "clear" in entry:
            if entry["clear"] is not True:
                failures.append("invalid isolated media thumbnail sequence")
                return
            normalized.append({"clear": True, "delay": float(delay)})
            continue
        path = Path(str(entry["path"]))
        if (
            path.is_absolute()
            or ".." in path.parts
            or path.suffix.lower() not in {".png", ".jpg", ".jpeg"}
            or not (runtime_sample / path).is_file()
        ):
            failures.append("invalid isolated media thumbnail sequence")
            return
        normalized.append({"path": str(path), "delay": float(delay)})
    command.extend([
        "--mwx-debug-scene-media-thumbnail-sequence-json",
        json.dumps(normalized, ensure_ascii=False, separators=(",", ":")),
    ])

def live_property_update_metrics(log_text: str) -> dict[str, Any] | None:
    match = LIVE_PROPERTY_UPDATE_RE.search(log_text)
    if match is None:
        return None

    def window_numbers(raw: str) -> list[int]:
        return [int(value) for value in raw.split(",") if value]

    return {
        "accepted": match.group("accepted") == "true",
        "surfaces_before": int(match.group("before")),
        "surfaces_after": int(match.group("after")),
        "windows_before": window_numbers(match.group("windows_before")),
        "windows_after": window_numbers(match.group("windows_after")),
        "keys": [value for value in match.group("keys").split(",") if value],
    }

def deferred_property_transition_metrics(log_text: str) -> dict[str, Any]:
    transition_lines = [
        line for line in log_text.splitlines()
        if "MWX deferred property transition:" in line
    ]
    resource_lines = [
        line for line in log_text.splitlines()
        if "MWX deferred base image:" in line
    ]
    transitions = [
        {
            "generation": int(match.group("generation")),
            "layer_ids": [
                int(value) for value in match.group("layers").split(",")
            ],
            "state": match.group("state"),
        }
        for match in DEFERRED_PROPERTY_TRANSITION_RE.finditer(log_text)
    ]
    resource_outcomes = [
        {
            "scene_generation": int(match.group("scene_generation")),
            "request_generation": int(match.group("request_generation")),
            "layer_id": int(match.group("layer")),
            "status": match.group("status"),
        }
        for match in DEFERRED_BASE_IMAGE_RE.finditer(log_text)
    ]
    failures: list[str] = []
    if len(transition_lines) != len(transitions):
        failures.append("deferred property transition evidence malformed")
    if len(resource_lines) != len(resource_outcomes):
        failures.append("deferred base image evidence malformed")

    by_generation: dict[int, list[dict[str, Any]]] = {}
    for transition in transitions:
        by_generation.setdefault(transition["generation"], []).append(
            transition
        )
    terminal_prefixes = ("committed", "superseded", "failed:", "cancelled:")
    pending_generations: list[int] = []
    committed_generations: list[int] = []
    terminal_generations: list[int] = []
    for generation, records in sorted(by_generation.items()):
        pending = [record for record in records if record["state"] == "pending"]
        terminals = [
            record for record in records
            if record["state"].startswith(terminal_prefixes)
        ]
        if pending:
            pending_generations.append(generation)
        if any(record["state"] == "committed" for record in terminals):
            committed_generations.append(generation)
        if terminals:
            terminal_generations.append(generation)
        if len(pending) != 1:
            failures.append(
                "deferred property generation missing unique pending state"
            )
        if len(terminals) != 1:
            failures.append(
                "deferred property generation missing unique terminal state"
            )
        if pending and terminals and records.index(pending[0]) > records.index(terminals[0]):
            failures.append("deferred property terminal preceded pending state")
        if pending and terminals and pending[0]["layer_ids"] != terminals[0]["layer_ids"]:
            failures.append("deferred property terminal layer identity mismatch")

    return {
        "has_evidence": bool(transition_lines or resource_lines),
        "transition_count": len(transitions),
        "resource_outcome_count": len(resource_outcomes),
        "pending_generations": pending_generations,
        "committed_generations": committed_generations,
        "terminal_generations": terminal_generations,
        "transitions": transitions,
        "resource_outcomes": resource_outcomes,
        "contract_succeeded": not failures,
        "validation_failures": sorted(set(failures)),
    }

def live_property_update_failures(
    requested: Any,
    metrics: dict[str, Any] | None,
) -> list[str]:
    if not isinstance(requested, dict) or not requested:
        return []
    if metrics is None:
        return ["live property update evidence missing"]

    failures: list[str] = []
    if not metrics["accepted"]:
        failures.append("live property update rejected")
    if metrics["surfaces_before"] != metrics["surfaces_after"]:
        failures.append("live property update changed Scene surface count")
    if metrics["windows_before"] != metrics["windows_after"]:
        failures.append("live property update replaced Scene windows")
    if metrics["keys"] != sorted(requested):
        failures.append("live property update key evidence mismatch")
    return failures

def live_property_output_failures(
    sample: dict[str, Any],
    motion: dict[str, Any] | None,
) -> list[str]:
    minimum = sample.get("minimum_live_changed_ratio")
    if minimum is None:
        return []
    if motion is None or motion["changed_ratio"] < float(minimum):
        return ["live property output evidence below minimum"]
    return []
