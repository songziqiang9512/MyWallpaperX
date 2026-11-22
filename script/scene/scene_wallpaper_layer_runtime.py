"""Observe particle, solid, puppet and audio input runtime contracts."""

from __future__ import annotations

import json
import math
import re
from pathlib import Path
from typing import Any


PARTICLE_LOADED_RE = re.compile(
    r"^particle loaded: (?P<loaded>\d+) / (?P<total>\d+)$",
    re.MULTILINE,
)

PARTICLE_REFRACT_LOADED_RE = re.compile(
    r"^particle refract loaded: (?P<count>\d+)$",
    re.MULTILINE,
)

PARTICLE_INITIAL_LIVE_RE = re.compile(
    r"^particle initial live: (?P<live>\d+)$",
    re.MULTILINE,
)

PARTICLE_AUTHORED_RE = re.compile(r"^particle authored: (?P<count>\d+)$", re.MULTILINE)

PARTICLE_VISIBLE_RE = re.compile(r"^particle visible: (?P<count>\d+)$", re.MULTILINE)

PARTICLE_SKIPPED_HIDDEN_RE = re.compile(
    r"^particle skipped hidden: (?P<count>\d+)$",
    re.MULTILINE,
)

PARTICLE_SKIPPED_TRANSPARENT_RE = re.compile(
    r"^particle skipped transparent: (?P<count>\d+)$",
    re.MULTILINE,
)

PARTICLE_LAYER_OK_RE = re.compile(r'^particle layer (?P<id>\d+) .*: OK ', re.MULTILINE)

PARTICLE_LAYER_UNAVAILABLE_RE = re.compile(
    r'^particle layer (?P<id>\d+) "(?P<name>.*)": unavailable$',
    re.MULTILINE,
)

# Mirrors SceneParticlePlaybackState.loadReportLines: the Swift side always
# emits the " detail=" suffix (possibly empty), so a non-greedy path keeps the
# split total even when a path itself contains " detail=".
PARTICLE_DIAGNOSTIC_RE = re.compile(
    r"^particle diagnostic (?P<kind>\S+) layer=(?P<layer>\S+) "
    r"path=(?P<path>.+?) detail=(?P<detail>.*)$",
    re.MULTILINE,
)

PARTICLE_STICKY_LOADED_RE = re.compile(
    r"^particle sticky loaded: (?P<loaded>\d+) / (?P<total>\d+)$",
    re.MULTILINE,
)

PARTICLE_CURRENT_NONEMPTY_RE = re.compile(
    r"^particle current nonempty: layers=\[(?P<ids>\d+(?:, \d+)*)?\]$", re.MULTILINE,
)

PARTICLE_COMMITTED_NONEMPTY_RE = re.compile(
    r"^particle committed nonempty: layers=\[(?P<ids>\d+(?:, \d+)*)?\]$", re.MULTILINE,
)

AUDIO_SCALED_VALUE_PROGRAM_RE = re.compile(
    r"^scene audio scaled value: schema=bounded-audio-scaled-value-v1 "
    r"bindings=(?P<bindings>\d+) "
    r"rejectedParticleLayerIDs=\[(?P<rejected_particle>[^\]]*)\] "
    r"rejectedScaleLayerIDs=\[(?P<rejected_scale>[^\]]*)\] "
    r"resolution=16$",
    re.MULTILINE,
)

SOLID_LAYER_COUNT_RE = re.compile(r"^solidLayerCount: (?P<count>\d+)$", re.MULTILINE)

SOLID_LAYER_OK_RE = re.compile(
    r'^layer (?P<id>\d+) .*: OK procedural solid(?:\s|$)',
    re.MULTILINE,
)

# The world-space puppet batch (cbd126d3) renamed the line from
# "puppet animation OK" to "puppet world geometry OK MDL<v>"; mode/ids/clips
# kept their shape.
PUPPET_ANIMATION_OK_RE = re.compile(
    r'^layer (?P<id>\d+) .*?: .*puppet world geometry OK \S+ '
    r'mode=(?P<mode>[a-z-]+) ids=(?P<ids>[\d,]+) clips=(?P<clips>\d+)(?:\s|$)',
    re.MULTILINE,
)

def particle_runtime_metrics(preview_text: str) -> dict[str, Any]:
    loaded_matches = list(PARTICLE_LOADED_RE.finditer(preview_text))
    loaded_match = loaded_matches[-1] if loaded_matches else None
    refract_loaded_match = PARTICLE_REFRACT_LOADED_RE.search(preview_text)
    initial_live_match = PARTICLE_INITIAL_LIVE_RE.search(preview_text)
    authored_match = PARTICLE_AUTHORED_RE.search(preview_text)
    visible_match = PARTICLE_VISIBLE_RE.search(preview_text)
    skipped_hidden_match = PARTICLE_SKIPPED_HIDDEN_RE.search(preview_text)
    skipped_transparent_match = PARTICLE_SKIPPED_TRANSPARENT_RE.search(preview_text)
    sticky_matches = list(PARTICLE_STICKY_LOADED_RE.finditer(preview_text))
    sticky_loaded_match = sticky_matches[-1] if sticky_matches else None
    current_nonempty = list(PARTICLE_CURRENT_NONEMPTY_RE.finditer(preview_text))
    committed_nonempty = list(PARTICLE_COMMITTED_NONEMPTY_RE.finditer(preview_text))

    def layer_ids(matches: list[re.Match[str]]) -> list[int] | None:
        if not matches:
            return None
        return [int(value) for value in (matches[-1].group("ids") or "").split(", ") if value]

    loaded = int(loaded_match.group("loaded")) if loaded_match else 0
    candidates = int(loaded_match.group("total")) if loaded_match else 0
    return {
        "has_load_evidence": loaded_match is not None,
        "current_nonempty_layer_ids": layer_ids(current_nonempty),
        "committed_nonempty_layer_ids": layer_ids(committed_nonempty),
        "has_initial_live_evidence": initial_live_match is not None,
        "has_visibility_evidence": all(
            match is not None
            for match in (authored_match, visible_match, skipped_hidden_match)
        ),
        "loaded": loaded,
        "candidates": candidates,
        "loaded_ratio": loaded / candidates if candidates else 0.0,
        "has_refract_evidence": refract_loaded_match is not None,
        "refract_loaded": int(refract_loaded_match.group("count"))
        if refract_loaded_match else 0,
        "initial_live": int(initial_live_match.group("live")) if initial_live_match else 0,
        "authored": int(authored_match.group("count")) if authored_match else 0,
        "visible": int(visible_match.group("count")) if visible_match else 0,
        "skipped_hidden": int(skipped_hidden_match.group("count")) if skipped_hidden_match else 0,
        "has_transparent_evidence": skipped_transparent_match is not None,
        "skipped_transparent": int(skipped_transparent_match.group("count"))
        if skipped_transparent_match else 0,
        "sticky_loaded": int(sticky_loaded_match.group("loaded"))
        if sticky_loaded_match else None,
        "sticky_total": int(sticky_loaded_match.group("total"))
        if sticky_loaded_match else None,
        "loaded_layer_ids": [int(match.group("id")) for match in PARTICLE_LAYER_OK_RE.finditer(preview_text)],
        "unavailable_layer_ids": [
            int(match.group("id"))
            for match in PARTICLE_LAYER_UNAVAILABLE_RE.finditer(preview_text)
        ],
        "particle_diagnostics": [
            {
                "kind": match.group("kind"),
                "layer": match.group("layer"),
                "path": match.group("path"),
                "detail": match.group("detail"),
            }
            for match in PARTICLE_DIAGNOSTIC_RE.finditer(preview_text)
        ],
    }

def audio_scaled_value_evidence_metrics(
    preview_text: str,
    evidence_path: Path,
) -> dict[str, Any]:
    program_match = AUDIO_SCALED_VALUE_PROGRAM_RE.search(preview_text)
    expected_count = int(program_match.group("bindings")) if program_match else 0
    rejected_particle_layer_ids = []
    rejected_scale_layer_ids = []
    if program_match:
        rejected_particle_layer_ids = [
            int(value.strip())
            for value in program_match.group("rejected_particle").split(",")
            if value.strip()
        ]
        rejected_scale_layer_ids = [
            int(value.strip())
            for value in program_match.group("rejected_scale").split(",")
            if value.strip()
        ]
    result: dict[str, Any] = {
        "has_evidence": False,
        "schema_version": None,
        "expected_binding_count": expected_count,
        "rejected_particle_layer_ids": rejected_particle_layer_ids,
        "rejected_scale_layer_ids": rejected_scale_layer_ids,
        "frame_index": None,
        "audio_generation": None,
        "audio_was_silent": None,
        "bindings": [],
        "failures": [],
    }
    if expected_count == 0 and not evidence_path.is_file():
        return result
    if not evidence_path.is_file():
        result["failures"].append("audio scaled value evidence missing")
        return result
    try:
        payload = json.loads(evidence_path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as error:
        result["failures"].append(f"audio scaled value evidence unreadable: {error}")
        return result
    result["has_evidence"] = True
    result["schema_version"] = payload.get("schemaVersion")
    result["frame_index"] = payload.get("frameIndex")
    result["audio_generation"] = payload.get("audioGeneration")
    result["audio_was_silent"] = payload.get("audioWasSilent")
    bindings = payload.get("bindings")
    if result["schema_version"] != 1:
        result["failures"].append("audio scaled value schema mismatch")
    if type(result["frame_index"]) is not int or result["frame_index"] <= 0:
        result["failures"].append("audio scaled value frame identity invalid")
    if type(result["audio_generation"]) is not int:
        result["failures"].append("audio scaled value generation invalid")
    if type(result["audio_was_silent"]) is not bool:
        result["failures"].append("audio scaled value silence identity invalid")
    if not isinstance(bindings, list):
        result["failures"].append("audio scaled value bindings malformed")
        return result
    normalized = []
    identities = []
    for binding in bindings:
        if not isinstance(binding, dict):
            result["failures"].append("audio scaled value binding malformed")
            continue
        layer_id = binding.get("layerID")
        target = binding.get("target")
        values = binding.get("effectiveValue")
        live_count = binding.get("liveParticleCount")
        if type(layer_id) is not int:
            result["failures"].append("audio scaled value layer identity invalid")
            continue
        expected_components = {"particle.rate": 1, "layer.scale": 3}.get(target)
        if expected_components is None:
            result["failures"].append("audio scaled value target identity invalid")
            continue
        if (
            not isinstance(values, list)
            or len(values) != expected_components
            or any(
                not isinstance(value, (int, float))
                or not math.isfinite(value)
                or value < 0
                for value in values
            )
        ):
            result["failures"].append("audio scaled value value invalid")
            continue
        if target == "particle.rate":
            if type(live_count) is not int or live_count < 0:
                result["failures"].append("audio scaled value live count invalid")
                continue
        elif live_count is not None:
            result["failures"].append("audio scaled value non-particle count invalid")
            continue
        identities.append((layer_id, target))
        normalized.append({
            "layer_id": layer_id,
            "target": target,
            "effective_value": [float(value) for value in values],
            "live_particle_count": live_count,
        })
    if len(normalized) != expected_count:
        result["failures"].append("audio scaled value binding count mismatch")
    if len(set(identities)) != len(identities):
        result["failures"].append("audio scaled value target identity duplicated")
    result["bindings"] = sorted(
        normalized, key=lambda item: (item["layer_id"], item["target"])
    )
    result["failures"] = list(dict.fromkeys(result["failures"]))
    return result

def solid_runtime_metrics(preview_text: str) -> dict[str, Any]:
    count_match = SOLID_LAYER_COUNT_RE.search(preview_text)
    loaded_layer_ids = [
        int(match.group("id")) for match in SOLID_LAYER_OK_RE.finditer(preview_text)
    ]
    candidates = int(count_match.group("count")) if count_match else 0
    return {
        "has_count_evidence": count_match is not None,
        "loaded": len(loaded_layer_ids),
        "candidates": candidates,
        "loaded_ratio": len(loaded_layer_ids) / candidates if candidates else 0.0,
        "loaded_layer_ids": loaded_layer_ids,
    }

def puppet_animation_runtime_metrics(preview_text: str) -> dict[str, Any]:
    entries = [
        {
            "layer_id": int(match.group("id")),
            "mode": match.group("mode"),
            "animation_ids": [
                int(animation_id)
                for animation_id in match.group("ids").split(",")
            ],
            "clip_count": int(match.group("clips")),
        }
        for match in PUPPET_ANIMATION_OK_RE.finditer(preview_text)
    ]
    entries.sort(key=lambda entry: entry["layer_id"])
    return {
        "layer_ids": [entry["layer_id"] for entry in entries],
        "layered_layer_ids": [
            entry["layer_id"]
            for entry in entries
            if entry["mode"] == "layered"
        ],
        "clip_count": sum(entry["clip_count"] for entry in entries),
        "entries": entries,
    }

def puppet_animation_runtime_failures(
    sample: dict[str, Any],
    metrics: dict[str, Any],
) -> list[str]:
    failures: list[str] = []
    expected_layer_ids = sample.get("expected_puppet_animation_layer_ids")
    if expected_layer_ids is not None:
        if metrics["layer_ids"] != sorted(int(value) for value in expected_layer_ids):
            failures.append("puppet animation layer IDs mismatch")
    expected_layered_layer_ids = sample.get(
        "expected_puppet_layered_layer_ids"
    )
    if expected_layered_layer_ids is not None:
        if metrics["layered_layer_ids"] != sorted(
            int(value) for value in expected_layered_layer_ids
        ):
            failures.append("puppet layered layer IDs mismatch")
    expected_clip_count = sample.get("expected_puppet_animation_clip_count")
    if expected_clip_count is not None:
        if metrics["clip_count"] != int(expected_clip_count):
            failures.append("puppet animation clip count mismatch")
    return failures

def solid_runtime_failures(
    sample: dict[str, Any],
    metrics: dict[str, Any],
) -> list[str]:
    failures: list[str] = []
    requires_count_evidence = (
        "expected_solid_candidates" in sample
        or bool(sample.get("required_solid_loaded_layer_ids"))
    )
    if requires_count_evidence and not metrics["has_count_evidence"]:
        failures.append("solid layer count evidence missing")
    elif "expected_solid_candidates" in sample:
        if metrics["candidates"] != int(sample["expected_solid_candidates"]):
            failures.append("solid layer candidate count mismatch")

    loaded_layer_ids = set(metrics["loaded_layer_ids"])
    for layer_id in sample.get("required_solid_loaded_layer_ids", []):
        if layer_id not in loaded_layer_ids:
            failures.append(f"solid layer {layer_id} should be loaded")
    return failures

def startup_runtime_failures(
    sample: dict[str, Any],
    elapsed_ms: float | None,
) -> list[str]:
    if elapsed_ms is None:
        return ["missing startup ready elapsed evidence"]
    if not math.isfinite(elapsed_ms) or elapsed_ms < 0:
        return ["invalid startup ready elapsed evidence"]
    maximum = sample.get("maximum_startup_ready_ms")
    if maximum is None:
        return []
    if type(maximum) not in (int, float) or not math.isfinite(maximum) or maximum <= 0:
        return ["invalid startup ready budget"]
    if elapsed_ms > maximum:
        return ["startup ready elapsed exceeds maximum"]
    return []

def particle_runtime_failures(
    sample: dict[str, Any],
    metrics: dict[str, Any],
) -> list[str]:
    failures: list[str] = []
    required_nonempty = sample.get("required_particle_committed_nonempty_layer_ids", [])
    committed_nonempty = metrics.get("committed_nonempty_layer_ids")
    if required_nonempty and committed_nonempty is None:
        failures.append("particle committed nonempty evidence missing")
    elif required_nonempty:
        for layer_id in required_nonempty:
            if layer_id not in committed_nonempty:
                failures.append(f"particle layer {layer_id} should produce a committed nonempty batch")
    if not metrics["has_load_evidence"]:
        failures.append("particle load evidence missing")
    else:
        if metrics["loaded"] < metrics["candidates"]:
            failures.append("particle loading incomplete")
        if metrics["loaded"] < int(sample.get("minimum_particle_loaded", 0)):
            failures.append("particle loaded count below minimum")
        expected_candidates = sample.get("expected_particle_candidates")
        if expected_candidates is not None and metrics["candidates"] != int(expected_candidates):
            failures.append("particle candidate count mismatch")

    if "minimum_particle_initial_live" in sample:
        if not metrics["has_initial_live_evidence"]:
            failures.append("particle initial live evidence missing")
        elif metrics["initial_live"] < int(sample["minimum_particle_initial_live"]):
            failures.append("particle initial live count below minimum")
    visibility_expectations = {
        "expected_particle_authored": "authored",
        "expected_particle_visible": "visible",
        "expected_particle_skipped_hidden": "skipped_hidden",
    }
    if any(key in sample for key in visibility_expectations) and not metrics["has_visibility_evidence"]:
        failures.append("particle visibility evidence missing")
    else:
        for expectation, metric in visibility_expectations.items():
            if expectation in sample and metrics[metric] != int(sample[expectation]):
                failures.append(f"particle {metric} count mismatch")
    if "expected_particle_skipped_transparent" in sample:
        if not metrics["has_transparent_evidence"]:
            failures.append("particle transparent visibility evidence missing")
        elif metrics["skipped_transparent"] != int(
            sample["expected_particle_skipped_transparent"]
        ):
            failures.append("particle skipped transparent count mismatch")
    loaded_layer_ids = set(metrics["loaded_layer_ids"])
    for layer_id in sample.get("required_particle_loaded_layer_ids", []):
        if layer_id not in loaded_layer_ids:
            failures.append(f"particle layer {layer_id} should be loaded")
    if "expected_particle_refract_loaded" in sample:
        if not metrics["has_refract_evidence"]:
            failures.append("particle refract evidence missing")
        elif metrics["refract_loaded"] != int(sample["expected_particle_refract_loaded"]):
            failures.append("particle refract loaded count mismatch")
    return failures
