"""Parse and summarize strict window-scoped Scene performance evidence."""

from __future__ import annotations

import math
import re
from typing import Any


FLOAT_PATTERN = r"[-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?"

PERFORMANCE_LINE_RE = re.compile(r"phase=performance (?P<fields>[^\r\n]+)")

PERFORMANCE_STAGES_LINE_RE = re.compile(
    r"phase=performance-stages (?P<fields>[^\r\n]*)"
)

PERFORMANCE_FRAME_STAGES_LINE_RE = re.compile(
    r"phase=performance-stages-frames (?P<fields>[^\r\n]*)"
)

PERFORMANCE_RESOURCES_LINE_RE = re.compile(
    r"phase=performance-resources (?P<fields>[^\r\n]+)"
)

PERFORMANCE_GPU_LINE_RE = re.compile(
    r"phase=performance-gpu (?P<fields>[^\r\n]+)"
)

# Window-scoped GPU operation census: counts of encoded passes and
# whole-texture copies. Deliberately has no duration field — Metal exposes
# per-command-buffer GPU time only, so these counts aim a composition change and
# the GPU number above judges it.
PERFORMANCE_GPU_CENSUS_FIELDS: dict[str, str] = {
    "frames": "frames",
    "mainPassRenders": "main_pass_render_passes",
    "depthRenders": "depth_render_passes",
    "offscreenRenders": "offscreen_render_passes",
    "resolvedMaterialRenders": "resolved_material_render_passes",
    "graphResourceSourceCaptures": "graph_resource_source_captures",
    "graphResourceInitializations": "graph_resource_initializations",
    "offscreenEffectCaptures": "offscreen_effect_captures",
    "textureCopyPasses": "texture_copy_passes",
    "framebufferCaptures": "framebuffer_captures",
    "framebufferCaptureBytes": "framebuffer_capture_bytes",
    "graphOutputPublicationCopies": "graph_output_publication_copies",
    "textureCopyBytes": "texture_copy_bytes",
    "unmeasuredCopyPasses": "unmeasured_copy_passes",
}

# The four offscreen categories must partition `offscreen_render_passes`; a
# mismatch means either a new encoder site was not classified or a counter was
# double-counted, and the census cannot be trusted for attribution.
PERFORMANCE_GPU_OFFSCREEN_CATEGORIES = (
    "resolved_material_render_passes",
    "graph_resource_source_captures",
    "graph_resource_initializations",
    "offscreen_effect_captures",
)

PERFORMANCE_STAGE_RE = re.compile(
    rf"(?P<name>[a-z0-9]+(?:-[a-z0-9]+)*)="
    rf"p50:(?P<p50>{FLOAT_PATTERN})ms "
    rf"p95:(?P<p95>{FLOAT_PATTERN})ms "
    r"n:(?P<sample_count>\d+)"
)

PERFORMANCE_INT_FIELDS = {
    "targetFPS": "target_fps",
    "callbacks": "driver_callbacks",
    "submitted": "submitted_frames",
    "completed": "completed_frames",
    "failed": "failed_frames",
    "presented": "presented_frames",
    "presentStreams": "presentation_stream_count",
    "presentIntervals": "presentation_interval_count",
    "presentOver1_5Budget": "presentation_over_1_5_budget",
    "callbackOver16": "callback_over_16_67_ms",
    "callbackOver33": "callback_over_33_33_ms",
    "discontinuities": "discontinuity_count",
    "drawableMissed": "drawable_missed",
    "cpuOver16": "cpu_over_16_67_ms",
    "cpuOver33": "cpu_over_33_33_ms",
    "gpuSamples": "gpu_samples",
    "gpuOver16": "gpu_over_16_67_ms",
    "gpuOver33": "gpu_over_33_33_ms",
}

PERFORMANCE_FLOAT_FIELDS = {
    "warmupSeconds": "measurement_warmup_seconds",
    "elapsed": "measurement_elapsed_seconds",
    "submittedFPS": "submitted_fps_total",
    "completedFPS": "completed_fps_total",
    "presentP50MS": "actual_present_p50_ms",
    "presentP95MS": "actual_present_p95_ms",
    "presentP99MS": "actual_present_p99_ms",
    "presentMaxMS": "actual_present_max_ms",
    "callbackP50MS": "callback_p50_ms",
    "callbackP95MS": "callback_p95_ms",
    "callbackMaxMS": "callback_max_ms",
    "droppedMS": "dropped_frame_time_ms",
    "maxRawFrameMS": "maximum_raw_frame_time_ms",
    "drawableWaitP95MS": "drawable_wait_p95_ms",
    "drawableWaitMaxMS": "drawable_wait_max_ms",
    "preEncodeP95MS": "pre_encode_p95_ms",
    "preEncodeMaxMS": "pre_encode_max_ms",
    "mainFrameP95MS": "main_frame_p95_ms",
    "mainFrameMaxMS": "main_frame_max_ms",
    "cpuP50MS": "cpu_frame_p50_ms",
    "cpuP95MS": "cpu_frame_p95_ms",
    "cpuMaxMS": "cpu_frame_max_ms",
    "gpuP50MS": "gpu_frame_p50_ms",
    "gpuP95MS": "gpu_frame_p95_ms",
    "gpuMaxMS": "gpu_frame_max_ms",
}

PERFORMANCE_RESOURCE_INT_FIELDS = {
    "samples": "sample_count",
    "processSamples": "process_sample_count",
    "processFootprintSampledPeakBytes": "process_footprint_sampled_peak_bytes",
    "gpuAllocatedSampledPeakBytes": "gpu_allocated_sampled_peak_bytes",
    "renderTargetPoolSampledPeakBytes": "render_target_pool_sampled_peak_bytes",
}

PERFORMANCE_RESOURCE_FLOAT_FIELDS = {
    "processCPUTimeMS": "process_cpu_time_ms",
}

PERFORMANCE_RESOURCE_STRING_FIELDS = {
    "processCPUTimeStatus": "process_cpu_time_status",
}

PERFORMANCE_RESOURCE_CPU_UNAVAILABLE_STATUSES = {
    "process-sample-unavailable",
    "resource-usage-unavailable",
    "raw-tick-sum-overflow",
    "tick-counter-regressed",
    "timebase-unavailable",
    "timebase-invalid",
    "conversion-overflow",
}

def _performance_stage_metrics(
    log_text: str,
    pattern: re.Pattern[str],
    label: str,
) -> dict[str, Any]:
    matches = list(pattern.finditer(log_text))
    if len(matches) != 1:
        return {
            "available": False,
            "error": f"expected one {label} event, found {len(matches)}",
        }

    fields = matches[0].group("fields")
    parsed: dict[str, dict[str, Any]] = {}
    cursor = 0
    try:
        while cursor < len(fields):
            while cursor < len(fields) and fields[cursor].isspace():
                cursor += 1
            if cursor == len(fields):
                break
            match = PERFORMANCE_STAGE_RE.match(fields, cursor)
            if match is None:
                token = fields[cursor:].split(maxsplit=1)[0]
                return {
                    "available": False,
                    "error": f"invalid performance stage token: {token}",
                }
            name = match.group("name")
            if name in parsed:
                return {
                    "available": False,
                    "error": f"duplicate performance stage: {name}",
                }
            p50_ms = float(match.group("p50"))
            p95_ms = float(match.group("p95"))
            sample_count = int(match.group("sample_count"))
            if not math.isfinite(p50_ms) or p50_ms < 0:
                raise ValueError(f"invalid performance stage p50: {name}")
            if not math.isfinite(p95_ms) or p95_ms < p50_ms:
                raise ValueError(f"invalid performance stage p95: {name}")
            if sample_count <= 0:
                raise ValueError(f"invalid performance stage sample count: {name}")
            parsed[name] = {
                "p50_ms": p50_ms,
                "p95_ms": p95_ms,
                "sample_count": sample_count,
            }
            cursor = match.end()
    except ValueError as error:
        return {"available": False, "error": str(error)}

    if not parsed:
        return {"available": False, "error": "performance stages are empty"}

    stages = {name: parsed[name] for name in sorted(parsed)}
    highest_name, highest = max(
        stages.items(),
        key=lambda item: item[1]["p95_ms"],
    )
    return {
        "available": True,
        "stages": stages,
        "highest_p95": {
            "name": highest_name,
            "milliseconds": highest["p95_ms"],
        },
    }

def performance_stage_metrics(log_text: str) -> dict[str, Any]:
    """Per-call stage percentiles; required evidence for a performance run."""
    return _performance_stage_metrics(
        log_text, PERFORMANCE_STAGES_LINE_RE, "performance stages"
    )

def performance_frame_stage_metrics(log_text: str) -> dict[str, Any] | None:
    """Per-frame stage totals.

    A nested stage that runs several times per frame is summed per frame here,
    which makes its figures additive against per-frame stages; the per-call
    percentiles above are not. Returns None for logs that predate this view so
    older evidence stays parseable.
    """
    if PERFORMANCE_FRAME_STAGES_LINE_RE.search(log_text) is None:
        return None
    return _performance_stage_metrics(
        log_text, PERFORMANCE_FRAME_STAGES_LINE_RE, "performance frame stages"
    )

def performance_gpu_census_metrics(log_text: str) -> dict[str, Any] | None:
    """Window-scoped GPU operation census.

    Counts encoded passes and whole-texture copies so a composition change can
    name the operation it removes. Returns None for logs that predate the census
    so older evidence stays parseable; once the line is present it is validated
    strictly and every failure makes the whole performance evidence unavailable.
    """
    matches = list(PERFORMANCE_GPU_LINE_RE.finditer(log_text))
    if not matches:
        return None
    if len(matches) != 1:
        return {
            "available": False,
            "error": f"expected one performance gpu census event, found {len(matches)}",
        }

    raw_fields: dict[str, str] = {}
    for token in matches[0].group("fields").split():
        if token.count("=") != 1:
            return {
                "available": False,
                "error": f"invalid performance gpu census token: {token}",
            }
        key, value = token.split("=", 1)
        if not key or not value:
            return {
                "available": False,
                "error": f"invalid performance gpu census token: {token}",
            }
        if key in raw_fields:
            return {
                "available": False,
                "error": f"duplicate performance gpu census field: {key}",
            }
        raw_fields[key] = value

    missing = sorted(set(PERFORMANCE_GPU_CENSUS_FIELDS) - raw_fields.keys())
    if missing:
        return {
            "available": False,
            "error": "missing performance gpu census fields: " + ", ".join(missing),
        }

    metrics: dict[str, Any] = {"available": True}
    try:
        for source, destination in PERFORMANCE_GPU_CENSUS_FIELDS.items():
            value = int(raw_fields[source])
            if value < 0:
                raise ValueError(f"negative performance gpu census field: {source}")
            metrics[destination] = value
    except ValueError as error:
        return {"available": False, "error": str(error)}

    frames = metrics["frames"]
    if frames <= 0:
        return {
            "available": False,
            "error": "performance gpu census frames must be positive",
        }
    subsets = (
        ("depth_render_passes", "main_pass_render_passes"),
        ("framebuffer_captures", "texture_copy_passes"),
        ("graph_output_publication_copies", "texture_copy_passes"),
        ("unmeasured_copy_passes", "texture_copy_passes"),
        ("framebuffer_capture_bytes", "texture_copy_bytes"),
    )
    for subset, superset in subsets:
        if metrics[subset] > metrics[superset]:
            return {
                "available": False,
                "error": f"performance gpu census {subset} exceeds {superset}",
            }
    offscreen_categories = sum(
        metrics[name] for name in PERFORMANCE_GPU_OFFSCREEN_CATEGORIES
    )
    if offscreen_categories != metrics["offscreen_render_passes"]:
        return {
            "available": False,
            "error": (
                "performance gpu census offscreen categories do not partition "
                f"offscreen renders: {offscreen_categories} != "
                f"{metrics['offscreen_render_passes']}"
            ),
        }
    metrics["per_frame"] = {
        destination: metrics[destination] / frames
        for destination in PERFORMANCE_GPU_CENSUS_FIELDS.values()
        if destination != "frames"
    }
    return metrics

def performance_resource_metrics(log_text: str) -> dict[str, Any]:
    matches = list(PERFORMANCE_RESOURCES_LINE_RE.finditer(log_text))
    if len(matches) != 1:
        return {
            "available": False,
            "error": f"expected one performance resources event, found {len(matches)}",
        }

    raw_fields: dict[str, str] = {}
    for token in matches[0].group("fields").split():
        if token.count("=") != 1:
            return {
                "available": False,
                "error": f"invalid performance resource token: {token}",
            }
        key, value = token.split("=", 1)
        if not key or not value:
            return {
                "available": False,
                "error": f"invalid performance resource token: {token}",
            }
        if key in raw_fields:
            return {
                "available": False,
                "error": f"duplicate performance resource field: {key}",
            }
        raw_fields[key] = value

    required = (
        set(PERFORMANCE_RESOURCE_INT_FIELDS)
        | set(PERFORMANCE_RESOURCE_FLOAT_FIELDS)
        | set(PERFORMANCE_RESOURCE_STRING_FIELDS)
    )
    missing = sorted(required - raw_fields.keys())
    if missing:
        return {
            "available": False,
            "error": "missing performance resource fields: " + ", ".join(missing),
        }
    unexpected = sorted(raw_fields.keys() - required)
    if unexpected:
        return {
            "available": False,
            "error": "unexpected performance resource fields: "
            + ", ".join(unexpected),
        }

    cpu_status = raw_fields["processCPUTimeStatus"]
    cpu_time = raw_fields["processCPUTimeMS"]
    if cpu_status != "available":
        if cpu_status not in PERFORMANCE_RESOURCE_CPU_UNAVAILABLE_STATUSES:
            return {
                "available": False,
                "error": f"invalid process CPU time status: {cpu_status}",
            }
        if cpu_time != "unavailable":
            return {
                "available": False,
                "error": "unavailable process CPU time must not contain a numeric value",
            }
        return {
            "available": False,
            "error": f"process CPU time unavailable: {cpu_status}",
        }
    if cpu_time == "unavailable":
        return {
            "available": False,
            "error": "available process CPU time is missing its numeric value",
        }

    metrics: dict[str, Any] = {
        "available": True,
        "process_cpu_time_status": cpu_status,
    }
    try:
        for source, destination in PERFORMANCE_RESOURCE_INT_FIELDS.items():
            value = int(raw_fields[source])
            if value < 0:
                raise ValueError(f"negative performance resource field: {source}")
            metrics[destination] = value
        for source, destination in PERFORMANCE_RESOURCE_FLOAT_FIELDS.items():
            value = float(raw_fields[source])
            if not math.isfinite(value) or value < 0:
                raise ValueError(f"invalid performance resource field: {source}")
            metrics[destination] = value
    except ValueError as error:
        return {"available": False, "error": str(error)}

    if metrics["sample_count"] < 2:
        return {
            "available": False,
            "error": "performance resource window requires at least two samples",
        }
    if metrics["process_sample_count"] != metrics["sample_count"]:
        return {
            "available": False,
            "error": "performance process sample identity mismatch",
        }
    return metrics

def performance_metrics(log_text: str, surface_count: int | None) -> dict[str, Any]:
    matches = list(PERFORMANCE_LINE_RE.finditer(log_text))
    if len(matches) != 1:
        return {
            "available": False,
            "error": f"expected one performance event, found {len(matches)}",
        }

    raw_fields: dict[str, str] = {}
    for token in matches[0].group("fields").split():
        if token.count("=") != 1:
            return {"available": False, "error": f"invalid performance token: {token}"}
        key, value = token.split("=", 1)
        if not key or not value:
            return {"available": False, "error": f"invalid performance token: {token}"}
        if key in raw_fields:
            return {"available": False, "error": f"duplicate performance field: {key}"}
        raw_fields[key] = value

    required = set(PERFORMANCE_INT_FIELDS) | set(PERFORMANCE_FLOAT_FIELDS)
    missing = sorted(required - raw_fields.keys())
    if missing:
        return {
            "available": False,
            "error": "missing performance fields: " + ", ".join(missing),
        }

    metrics: dict[str, Any] = {"available": True}
    try:
        for source, destination in PERFORMANCE_INT_FIELDS.items():
            value = int(raw_fields[source])
            if value < 0:
                raise ValueError(f"negative performance field: {source}")
            metrics[destination] = value
        for source, destination in PERFORMANCE_FLOAT_FIELDS.items():
            value = float(raw_fields[source])
            if not math.isfinite(value) or value < 0:
                raise ValueError(f"invalid performance field: {source}")
            metrics[destination] = value
    except ValueError as error:
        return {"available": False, "error": str(error)}

    elapsed = metrics["measurement_elapsed_seconds"]
    if elapsed <= 0:
        return {"available": False, "error": "performance elapsed must be positive"}
    if metrics["target_fps"] not in (30, 60):
        return {"available": False, "error": "performance target FPS must be 30 or 60"}
    if surface_count is None or surface_count <= 0:
        return {"available": False, "error": "performance surface count must be positive"}
    if metrics["presentation_stream_count"] != surface_count:
        return {
            "available": False,
            "error": "performance presentation stream count does not match surfaces",
        }
    expected_intervals = (
        metrics["presented_frames"] - metrics["presentation_stream_count"]
    )
    if expected_intervals <= 0:
        return {"available": False, "error": "actual-present intervals unavailable"}
    if metrics["presentation_interval_count"] != expected_intervals:
        return {"available": False, "error": "actual-present interval identity mismatch"}
    if metrics["presentation_over_1_5_budget"] > expected_intervals:
        return {"available": False, "error": "actual-present over-budget count invalid"}

    metrics["driver_fps"] = metrics["driver_callbacks"] / elapsed
    metrics["submitted_fps_per_surface"] = metrics["submitted_fps_total"] / surface_count
    metrics["completed_fps_per_surface"] = metrics["completed_fps_total"] / surface_count
    metrics["actual_present_over_1_5_budget_ratio"] = (
        metrics["presentation_over_1_5_budget"] / expected_intervals
    )
    stage_metrics = performance_stage_metrics(log_text)
    if stage_metrics.get("available") is not True:
        return {
            "available": False,
            "error": "performance stages unavailable: "
            + str(stage_metrics.get("error", "unknown error")),
        }
    metrics["cpu_stages"] = stage_metrics
    frame_stage_metrics = performance_frame_stage_metrics(log_text)
    if frame_stage_metrics is not None:
        if frame_stage_metrics.get("available") is not True:
            return {
                "available": False,
                "error": "performance frame stages unavailable: "
                + str(frame_stage_metrics.get("error", "unknown error")),
            }
        metrics["cpu_stages_frames"] = frame_stage_metrics
    resource_metrics = performance_resource_metrics(log_text)
    if resource_metrics.get("available") is not True:
        return {
            "available": False,
            "error": "performance resources unavailable: "
            + str(resource_metrics.get("error", "unknown error")),
        }
    minimum_resource_samples = max(2, math.floor(elapsed))
    if resource_metrics["sample_count"] < minimum_resource_samples:
        return {
            "available": False,
            "error": "performance resource sample density is below one hertz",
        }
    metrics["resources"] = resource_metrics
    gpu_census = performance_gpu_census_metrics(log_text)
    if gpu_census is not None:
        if gpu_census.get("available") is not True:
            return {
                "available": False,
                "error": "performance gpu census unavailable: "
                + str(gpu_census.get("error", "unknown error")),
            }
        metrics["gpu_census"] = gpu_census
    steady_state_reasons = []
    if metrics["measurement_warmup_seconds"] < 30:
        steady_state_reasons.append("measurement warmup is below 30 seconds")
    if elapsed < 60:
        steady_state_reasons.append("measurement elapsed is below 60 seconds")
    metrics["steady_state_eligible"] = not steady_state_reasons
    metrics["steady_state_ineligible_reasons"] = steady_state_reasons
    return metrics

def performance_failures(metrics: dict[str, Any]) -> list[str]:
    if metrics.get("available") is True:
        return []
    return [f"performance evidence unavailable: {metrics.get('error', 'unknown error')}"]

def summarize_performance(results: list[dict[str, Any]]) -> dict[str, Any]:
    available = [
        (str(result["id"]), result.get("runtime", {}).get("performance"))
        for result in results
        if result.get("runtime", {}).get("performance", {}).get("available") is True
    ]
    unavailable = len(results) - len(available)
    if not available:
        return {
            "available_count": 0,
            "unavailable_count": unavailable,
            "steady_state_eligible_count": 0,
            "steady_state_eligible_ids": [],
            "lowest_driver_fps": None,
            "slowest_startup_ready_ms": None,
            "highest_actual_present_p99_ms": None,
        }
    lowest_id, lowest = min(available, key=lambda item: item[1]["driver_fps"])
    startup_values = [
        (str(result["id"]), result.get("runtime", {}).get("startup_ready_ms"))
        for result in results
        if isinstance(result.get("runtime", {}).get("startup_ready_ms"), (int, float))
    ]
    slowest = max(startup_values, key=lambda item: item[1]) if startup_values else None
    highest_present_id, highest_present = max(
        available,
        key=lambda item: item[1]["actual_present_p99_ms"],
    )
    steady_state_eligible_ids = sorted(
        sample_id
        for sample_id, metrics in available
        if metrics.get("steady_state_eligible") is True
    )
    return {
        "available_count": len(available),
        "unavailable_count": unavailable,
        "steady_state_eligible_count": len(steady_state_eligible_ids),
        "steady_state_eligible_ids": steady_state_eligible_ids,
        "lowest_driver_fps": {"id": lowest_id, "fps": lowest["driver_fps"]},
        "slowest_startup_ready_ms": (
            {"id": slowest[0], "milliseconds": slowest[1]} if slowest else None
        ),
        "highest_actual_present_p99_ms": {
            "id": highest_present_id,
            "milliseconds": highest_present["actual_present_p99_ms"],
        },
    }
