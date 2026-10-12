"""Validate pointer requests and observe motion and cursor ripple evidence."""

from __future__ import annotations

import math
import re
from pathlib import Path
from scene_wallpaper_performance import FLOAT_PATTERN
from typing import Any
from web_benchmark_capture import png_motion_metrics


CURSOR_RIPPLE_STATE_RE = re.compile(
    r"phase=cursor-ripple-state layer=(?P<layer>-?\d+) "
    r"effect=(?P<effect>-?\d+) descriptor=(?P<descriptor>\S+) "
    r"status=completed width=(?P<width>\d+) height=(?P<height>\d+) "
    r"output=(?P<output>\S+) activePixels=(?P<active>\d+) "
    r"bounds=(?P<minimum_x>-?\d+),(?P<minimum_y>-?\d+),"
    r"(?P<maximum_x>-?\d+),(?P<maximum_y>-?\d+) "
    r"max=(?P<maximum>\d+) sum=(?P<sum>\d+) "
    rf"current=(?P<current_x>{FLOAT_PATTERN}),(?P<current_y>{FLOAT_PATTERN}) "
    rf"previous=(?P<previous_x>{FLOAT_PATTERN}),(?P<previous_y>{FLOAT_PATTERN}) "
    r"inside=(?P<inside>true|false) "
    r"previousInside=(?P<previous_inside>true|false) "
    rf"movement=(?P<movement>{FLOAT_PATTERN}) "
)

CURSOR_RIPPLE_VISIBLE_RE = re.compile(
    r"phase=cursor-ripple-visible layer=(?P<layer>-?\d+) "
    r"effect=(?P<effect>-?\d+) descriptor=(?P<descriptor>\S+) "
    r"status=completed width=(?P<width>\d+) height=(?P<height>\d+) "
    r"changedPixels=(?P<changed>\d+) "
    r"bounds=(?P<minimum_x>-?\d+),(?P<minimum_y>-?\d+),"
    r"(?P<maximum_x>-?\d+),(?P<maximum_y>-?\d+) "
    r"max=(?P<maximum>\d+) sum=(?P<sum>\d+) "
    rf"current=(?P<current_x>{FLOAT_PATTERN}),(?P<current_y>{FLOAT_PATTERN}) "
    rf"previous=(?P<previous_x>{FLOAT_PATTERN}),(?P<previous_y>{FLOAT_PATTERN}) "
    r"inside=(?P<inside>true|false) "
    r"previousInside=(?P<previous_inside>true|false) "
    rf"movement=(?P<movement>{FLOAT_PATTERN})"
)

def hover_pointer_normalized(
    sample: dict[str, Any],
) -> tuple[float, float] | None:
    raw = sample.get("hover_pointer_normalized")
    if raw is None:
        return None
    if (
        not isinstance(raw, list)
        or len(raw) != 2
        or any(type(value) not in (int, float) for value in raw)
    ):
        raise ValueError("hover_pointer_normalized must contain two numbers")
    x, y = (float(raw[0]), float(raw[1]))
    if not math.isfinite(x) or not math.isfinite(y) or not (-1 <= x <= 1 and -1 <= y <= 1):
        raise ValueError("hover_pointer_normalized must stay within [-1, 1]")
    return (x, y)

def pointer_trajectory_normalized(
    sample: dict[str, Any],
) -> list[tuple[float, float]] | None:
    raw = sample.get("pointer_trajectory_normalized")
    if raw is None:
        return None
    if not isinstance(raw, list) or not 2 <= len(raw) <= 8:
        raise ValueError(
            "pointer_trajectory_normalized must contain 2 to 8 points"
        )
    points: list[tuple[float, float]] = []
    for value in raw:
        if (
            not isinstance(value, list)
            or len(value) != 2
            or any(type(component) not in (int, float) for component in value)
        ):
            raise ValueError(
                "pointer_trajectory_normalized points must contain two numbers"
            )
        point = (float(value[0]), float(value[1]))
        if (
            not all(math.isfinite(component) for component in point)
            or not all(-1 <= component <= 1 for component in point)
        ):
            raise ValueError(
                "pointer_trajectory_normalized must stay within [-1, 1]"
            )
        if points and points[-1] == point:
            raise ValueError(
                "pointer_trajectory_normalized consecutive points must differ"
            )
        points.append(point)
    return points

def pointer_trajectory_minimum_changed_ratio(
    sample: dict[str, Any],
) -> float | None:
    raw = sample.get("minimum_pointer_trajectory_changed_ratio")
    if raw is None:
        return None
    if type(raw) not in (int, float):
        raise ValueError(
            "minimum_pointer_trajectory_changed_ratio must be a number"
        )
    value = float(raw)
    if not math.isfinite(value) or not 0 <= value <= 1:
        raise ValueError(
            "minimum_pointer_trajectory_changed_ratio must stay within [0, 1]"
        )
    return value

def pointer_trajectory_motion_metrics(
    ready_snapshot: Path,
    trajectory_snapshots: list[Path],
) -> list[dict[str, float] | None] | None:
    if not trajectory_snapshots:
        return None
    inputs = [ready_snapshot, *trajectory_snapshots]
    return [
        png_motion_metrics(before, after)
        for before, after in zip(inputs[:-1], inputs[1:], strict=True)
    ]

def hover_pointer_stationary_entry(sample: dict[str, Any]) -> bool:
    raw = sample.get("hover_pointer_stationary_entry", False)
    if type(raw) is not bool:
        raise ValueError("hover_pointer_stationary_entry must be a boolean")
    return raw

def hover_pointer_from_launch(sample: dict[str, Any]) -> bool:
    raw = sample.get("hover_pointer_from_launch", False)
    if type(raw) is not bool:
        raise ValueError("hover_pointer_from_launch must be a boolean")
    return raw

def cursor_primary_click(sample: dict[str, Any]) -> bool:
    raw = sample.get("cursor_primary_click", False)
    if type(raw) is not bool:
        raise ValueError("cursor_primary_click must be a boolean")
    return raw

def cursor_primary_click_subframe(sample: dict[str, Any]) -> bool:
    raw = sample.get("cursor_primary_click_subframe", False)
    if type(raw) is not bool:
        raise ValueError("cursor_primary_click_subframe must be a boolean")
    return raw

def cursor_drag_to_normalized(
    sample: dict[str, Any],
) -> tuple[float, float] | None:
    raw = sample.get("cursor_drag_to_normalized")
    if raw is None:
        return None
    if (
        not isinstance(raw, list)
        or len(raw) != 2
        or any(type(value) not in (int, float) for value in raw)
    ):
        raise ValueError("cursor_drag_to_normalized must contain two numbers")
    x, y = (float(raw[0]), float(raw[1]))
    if not math.isfinite(x) or not math.isfinite(y) or not (-1 <= x <= 1 and -1 <= y <= 1):
        raise ValueError("cursor_drag_to_normalized must stay within [-1, 1]")
    return (x, y)

def cursor_interaction_output_failures(
    sample: dict[str, Any],
    hover_motion: dict[str, dict[str, float] | None] | None,
    drag_pointer: tuple[float, float] | None,
) -> list[str]:
    response = sample.get("cursor_drag_response", "hold")
    if response == "spring-return":
        moved = (hover_motion or {}).get("before_to_drag")
        returned = (hover_motion or {}).get("before_to_spring_after")
        failures = []
        if moved is None or moved["changed_ratio"] <= float(sample.get("minimum_hover_changed_ratio", 0)):
            failures.append("spring drag has no visible displacement")
        return_space = sample.get("cursor_drag_return_space", "window")
        if return_space == "window":
            if returned is None or returned["changed_ratio"] > float(sample.get("maximum_drag_settle_changed_ratio", 0.001)):
                failures.append("spring drag did not return to its visible baseline")
        elif return_space == "puppet-source":
            # Post-deformation effects can continue animating after geometry
            # returns. The mandatory exact GPU-source/terminal-frame contract
            # is checked separately; visible displacement is still required.
            if not sample.get("puppet_interaction_layer_ids"):
                failures.append("source-space return requires explicit Puppet owners")
            if returned is None:
                failures.append("missing post-return window observation")
        else:
            failures.append("unknown spring return space")
        return failures
    if response not in {"hold", "no-capture"}:
        return ["unknown cursor drag response"]
    if response == "no-capture":
        return []  # The exact GPU-source no-capture contract is mandatory below.
    minimum = float(sample.get("minimum_hover_changed_ratio", 0))
    before = (hover_motion or {}).get("before_to_hover")
    after = (hover_motion or {}).get("hover_to_after")
    if drag_pointer is None:
        ratios = [
            metrics["changed_ratio"]
            for metrics in (before, after)
            if metrics is not None
        ]
        return (
            ["hover interaction output evidence below minimum"]
            if len(ratios) != 2 or min(ratios) <= minimum else []
        )
    failures: list[str] = []
    if before is None or before["changed_ratio"] <= minimum:
        failures.append("drag interaction output evidence below minimum")
    maximum_settle = float(sample.get("maximum_drag_settle_changed_ratio", 0.001))
    if after is None or after["changed_ratio"] > maximum_settle:
        failures.append("drag interaction output did not preserve settled position")
    return failures

def _cursor_ripple_propagation_metrics(
    log_text: str,
    pattern: re.Pattern[str],
    pixel_group: str,
) -> dict[str, Any]:
    grouped: dict[tuple[int, int, str], list[dict[str, Any]]] = {}
    for match in pattern.finditer(log_text):
        minimum_x = int(match.group("minimum_x"))
        minimum_y = int(match.group("minimum_y"))
        maximum_x = int(match.group("maximum_x"))
        maximum_y = int(match.group("maximum_y"))
        active_pixels = int(match.group(pixel_group))
        row = {
            "active_pixels": active_pixels,
            "bounds": [minimum_x, minimum_y, maximum_x, maximum_y],
            "bounds_width": (
                maximum_x - minimum_x + 1 if active_pixels > 0 else 0
            ),
            "bounds_height": (
                maximum_y - minimum_y + 1 if active_pixels > 0 else 0
            ),
            "maximum_channel": int(match.group("maximum")),
            "channel_sum": int(match.group("sum")),
            "inside": match.group("inside") == "true",
            "previous_inside": match.group("previous_inside") == "true",
            "movement": float(match.group("movement")),
        }
        identity = (
            int(match.group("layer")),
            int(match.group("effect")),
            match.group("descriptor"),
        )
        grouped.setdefault(identity, []).append(row)

    candidates: list[dict[str, Any]] = []
    for (layer, effect, descriptor), rows in grouped.items():
        injection_index = next((
            index
            for index, row in enumerate(rows)
            if row["inside"]
            and row["movement"] > 0
            and row["active_pixels"] > 0
        ), None)
        if injection_index is None:
            candidates.append({
                "layer": layer,
                "effect": effect,
                "descriptor": descriptor,
                "record_count": len(rows),
                "injection_found": False,
                "accepted": False,
            })
            continue
        injection = rows[injection_index]
        exit_index = next((
            index
            for index in range(injection_index + 1, len(rows))
            if not rows[index]["inside"]
        ), None)
        post_exit_rows = rows[exit_index:] if exit_index is not None else []
        consecutive_nonzero = 0
        for row in post_exit_rows:
            if row["active_pixels"] <= 0:
                break
            consecutive_nonzero += 1
        maximum_post_exit_width = max(
            (row["bounds_width"] for row in post_exit_rows),
            default=0,
        )
        maximum_post_exit_height = max(
            (row["bounds_height"] for row in post_exit_rows),
            default=0,
        )
        final = post_exit_rows[-1] if post_exit_rows else None
        expanded_width = maximum_post_exit_width > injection["bounds_width"]
        expanded_height = maximum_post_exit_height > injection["bounds_height"]
        peak_decay_ratio = (
            final["maximum_channel"] / injection["maximum_channel"]
            if final is not None and injection["maximum_channel"] > 0
            else None
        )
        peak_decayed = peak_decay_ratio is not None and peak_decay_ratio <= 0.8
        persisted_after_exit = consecutive_nonzero >= 3
        candidates.append({
            "layer": layer,
            "effect": effect,
            "descriptor": descriptor,
            "record_count": len(rows),
            "injection_found": True,
            "injection_record_index": injection_index,
            "injection_active_pixels": injection["active_pixels"],
            "injection_bounds": injection["bounds"],
            "injection_bounds_width": injection["bounds_width"],
            "injection_bounds_height": injection["bounds_height"],
            "injection_maximum_channel": injection["maximum_channel"],
            "exit_record_index": exit_index,
            "post_exit_nonzero_frames": consecutive_nonzero,
            "maximum_post_exit_active_pixels": max(
                (row["active_pixels"] for row in post_exit_rows),
                default=0,
            ),
            "maximum_post_exit_channel_sum": max(
                (row["channel_sum"] for row in post_exit_rows),
                default=0,
            ),
            "maximum_post_exit_bounds_width": maximum_post_exit_width,
            "maximum_post_exit_bounds_height": maximum_post_exit_height,
            "final_active_pixels": final["active_pixels"] if final else 0,
            "final_maximum_channel": final["maximum_channel"] if final else 0,
            "final_channel_sum": final["channel_sum"] if final else 0,
            "final_peak_ratio": peak_decay_ratio,
            "settled_to_zero": final is not None and final["active_pixels"] == 0,
            "expanded_width": expanded_width,
            "expanded_height": expanded_height,
            "persisted_after_exit": persisted_after_exit,
            "peak_decayed": peak_decayed,
            "accepted": (
                persisted_after_exit
                and expanded_width
                and expanded_height
                and peak_decayed
            ),
        })

    selected = next(
        (candidate for candidate in candidates if candidate["accepted"]),
        max(
            candidates,
            key=lambda candidate: (
                candidate.get("post_exit_nonzero_frames", 0),
                candidate.get("maximum_post_exit_active_pixels", 0),
            ),
            default=None,
        ),
    )
    return {
        "has_evidence": bool(grouped),
        "record_count": sum(len(rows) for rows in grouped.values()),
        "candidate_count": len(candidates),
        "accepted": selected is not None and selected["accepted"],
        "selected": selected,
        "candidates": candidates,
    }

def cursor_ripple_persistence_metrics(log_text: str) -> dict[str, Any]:
    return _cursor_ripple_propagation_metrics(
        log_text,
        CURSOR_RIPPLE_STATE_RE,
        "active",
    )

def cursor_ripple_visible_metrics(log_text: str) -> dict[str, Any]:
    metrics = _cursor_ripple_propagation_metrics(
        log_text,
        CURSOR_RIPPLE_VISIBLE_RE,
        "changed",
    )
    for candidate in metrics["candidates"]:
        peak = candidate.get("maximum_post_exit_channel_sum", 0)
        final = candidate.get("final_channel_sum", 0)
        ratio = final / peak if peak > 0 else None
        candidate["visible_sum_decay_ratio"] = ratio
        candidate["visible_sum_decayed"] = ratio is not None and ratio <= 0.8
        candidate["accepted"] = (
            candidate.get("persisted_after_exit", False)
            and candidate.get("expanded_width", False)
            and candidate.get("expanded_height", False)
            and candidate["visible_sum_decayed"]
        )
    metrics["selected"] = next(
        (candidate for candidate in metrics["candidates"] if candidate["accepted"]),
        max(
            metrics["candidates"],
            key=lambda candidate: (
                candidate.get("post_exit_nonzero_frames", 0),
                candidate.get("maximum_post_exit_active_pixels", 0),
            ),
            default=None,
        ),
    )
    metrics["accepted"] = (
        metrics["selected"] is not None and metrics["selected"]["accepted"]
    )
    return metrics

def cursor_ripple_persistence_failures(
    metrics: dict[str, Any],
    require_evidence: bool,
) -> list[str]:
    if not require_evidence:
        return []
    if not metrics["has_evidence"]:
        return ["cursor ripple GPU state evidence missing"]
    selected = metrics["selected"]
    if selected is None or not selected.get("injection_found", False):
        return ["cursor ripple movement injection evidence missing"]
    failures: list[str] = []
    if not selected["persisted_after_exit"]:
        failures.append("cursor ripple disappeared before three post-exit GPU frames")
    if not selected["expanded_width"] or not selected["expanded_height"]:
        failures.append("cursor ripple extent did not expand after pointer exit")
    if not selected["peak_decayed"]:
        failures.append("cursor ripple peak did not decay by twenty percent after exit")
    return failures

def cursor_ripple_visible_failures(
    metrics: dict[str, Any],
    require_evidence: bool,
) -> list[str]:
    if not require_evidence:
        return []
    if not metrics["has_evidence"]:
        return ["cursor ripple visible output evidence missing"]
    selected = metrics["selected"]
    if selected is None or not selected.get("injection_found", False):
        return ["cursor ripple visible movement injection evidence missing"]
    failures: list[str] = []
    if not selected["persisted_after_exit"]:
        failures.append(
            "cursor ripple visible output disappeared before three post-exit GPU frames"
        )
    if not selected["expanded_width"] or not selected["expanded_height"]:
        failures.append("cursor ripple visible output did not expand after pointer exit")
    if not selected["visible_sum_decayed"]:
        failures.append("cursor ripple visible output did not decay after pointer exit")
    return failures
