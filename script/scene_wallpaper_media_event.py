"""Media event parsing and isolated benchmark argument construction."""

from __future__ import annotations

import json
import math
import re
from pathlib import Path
from typing import Any


FLOAT_PATTERN = r"[-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?"
SCENE_SCRIPT_MEDIA_THUMBNAIL_COLOR_RE = re.compile(
    r"MWX SceneScript VM: "
    r"target=effectConstant\(layerID: (?P<layer>\d+), "
    r"effectIndex: (?P<effect>\d+), passIndex: (?P<pass>\d+), "
    r'name: "(?P<constant>[^"]+)"\) event=mediaThumbnailChanged '
    r"generation=(?P<generation>\d+) "
    r"hasThumbnail=(?P<has_thumbnail>true|false) "
    rf"primary=(?P<primary_red>{FLOAT_PATTERN}),"
    rf"(?P<primary_green>{FLOAT_PATTERN}),(?P<primary_blue>{FLOAT_PATTERN}) "
    rf"secondary=(?P<secondary_red>{FLOAT_PATTERN}),"
    rf"(?P<secondary_green>{FLOAT_PATTERN}),(?P<secondary_blue>{FLOAT_PATTERN}) "
    rf"tertiary=(?P<tertiary_red>{FLOAT_PATTERN}),"
    rf"(?P<tertiary_green>{FLOAT_PATTERN}),(?P<tertiary_blue>{FLOAT_PATTERN}) "
    rf"text=(?P<text_red>{FLOAT_PATTERN}),"
    rf"(?P<text_green>{FLOAT_PATTERN}),(?P<text_blue>{FLOAT_PATTERN}) "
    rf"highContrast=(?P<high_contrast_red>{FLOAT_PATTERN}),"
    rf"(?P<high_contrast_green>{FLOAT_PATTERN}),"
    rf"(?P<high_contrast_blue>{FLOAT_PATTERN}) "
    r"output=(?P<output_type>vector[23])\((?P<output>[^)]*)\) "
    r"mutations=(?P<mutations>\d+) route=(?P<route>\S+) "
    r"fallback=(?P<fallback>\S+)"
)
SCENE_SCRIPT_MEDIA_THUMBNAIL_LAYER_COLOR_RE = re.compile(
    r"MWX SceneScript VM: "
    r"target=layer\(layerID: (?P<layer>\d+), "
    r"field: [^)]*\.(?P<field>color)\) "
    r"event=mediaThumbnailChanged "
    r"generation=(?P<generation>\d+) "
    r"hasThumbnail=(?P<has_thumbnail>true|false) "
    rf"primary=(?P<primary_red>{FLOAT_PATTERN}),"
    rf"(?P<primary_green>{FLOAT_PATTERN}),(?P<primary_blue>{FLOAT_PATTERN}) "
    rf"secondary=(?P<secondary_red>{FLOAT_PATTERN}),"
    rf"(?P<secondary_green>{FLOAT_PATTERN}),(?P<secondary_blue>{FLOAT_PATTERN}) "
    rf"tertiary=(?P<tertiary_red>{FLOAT_PATTERN}),"
    rf"(?P<tertiary_green>{FLOAT_PATTERN}),(?P<tertiary_blue>{FLOAT_PATTERN}) "
    rf"text=(?P<text_red>{FLOAT_PATTERN}),"
    rf"(?P<text_green>{FLOAT_PATTERN}),(?P<text_blue>{FLOAT_PATTERN}) "
    rf"highContrast=(?P<high_contrast_red>{FLOAT_PATTERN}),"
    rf"(?P<high_contrast_green>{FLOAT_PATTERN}),"
    rf"(?P<high_contrast_blue>{FLOAT_PATTERN}) "
    r"output=(?P<output_type>vector[23])\((?P<output>[^)]*)\) "
    r"mutations=(?P<mutations>\d+) route=(?P<route>\S+) "
    r"fallback=(?P<fallback>\S+)"
)
SCENE_SCRIPT_VECTOR_MEDIA_STARTUP_PREFIX = "scene media thumbnail colors: "
SCENE_SCRIPT_VECTOR_MEDIA_STARTUP_RE = re.compile(
    r"scene media thumbnail colors: schema=(?P<schema>\S+) "
    r"bindings=(?P<bindings>\d+) activeBindings=(?P<active_bindings>\d+) "
    r"route=(?P<route>\S+) "
    r"fallback=(?P<fallback>\S+) reason=(?P<reason>\S+) "
    r"profile=(?P<profile>\S+) input=(?P<input>\S+) "
    r"liveProvider=(?P<live_provider>\S+) targets=(?P<targets>\[.*\])"
)

MEDIA_COLOR_FIELDS = (
    "primary_color",
    "secondary_color",
    "tertiary_color",
    "text_color",
    "high_contrast_color",
)
MEDIA_COLOR_EXPECTATION_COMMON_REQUIRED_FIELDS = frozenset({
    "layer_id",
    "generation",
    "has_thumbnail",
    "route",
    *MEDIA_COLOR_FIELDS,
})
MEDIA_COLOR_EXPECTATION_EFFECT_IDENTITY_FIELDS = frozenset({
    "effect_index",
    "pass_index",
    "constant",
})
MEDIA_COLOR_EXPECTATION_LAYER_IDENTITY_FIELDS = frozenset({
    "target_kind",
    "field",
})
MEDIA_COLOR_EXPECTATION_OPTIONAL_FIELDS = frozenset({
    "fallback",
    "mutations",
    "output_type",
    "output",
})
SCENE_SCRIPT_VECTOR_MEDIA_STARTUP_FIELDS = frozenset({
    "schema",
    "bindings",
    "active_bindings",
    "route",
    "fallback",
    "reason",
    "profile",
    "input",
    "live_provider",
    "targets",
})


def media_color_transition_metrics(log_text: str) -> list[dict[str, Any]]:
    """Return generic SceneScript thumbnail-color completions from a preview log."""

    completions: list[dict[str, Any]] = []
    for match in SCENE_SCRIPT_MEDIA_THUMBNAIL_COLOR_RE.finditer(log_text):
        completion = _media_color_completion(match)
        if completion is not None:
            completion.update({
                "target_kind": "effectConstant",
                "layer_id": int(match.group("layer")),
                "effect_index": int(match.group("effect")),
                "pass_index": int(match.group("pass")),
                "constant": match.group("constant"),
            })
            completions.append(completion)
    for match in SCENE_SCRIPT_MEDIA_THUMBNAIL_LAYER_COLOR_RE.finditer(log_text):
        completion = _media_color_completion(match)
        if completion is not None:
            completion.update({
                "target_kind": "layer",
                "layer_id": int(match.group("layer")),
                "field": match.group("field"),
            })
            completions.append(completion)
    completions.sort(key=_callback_identity)
    return completions


def _media_color_completion(match: re.Match[str]) -> dict[str, Any] | None:
    try:
        output = [
            float(component.strip())
            for component in match.group("output").split(",")
        ]
    except ValueError:
        return None
    expected_component_count = (
        2 if match.group("output_type") == "vector2" else 3
    )
    if len(output) != expected_component_count:
        return None
    return {
        "generation": int(match.group("generation")),
        "has_thumbnail": match.group("has_thumbnail") == "true",
        "primary_color": [
            float(match.group("primary_red")),
            float(match.group("primary_green")),
            float(match.group("primary_blue")),
        ],
        "secondary_color": [
            float(match.group("secondary_red")),
            float(match.group("secondary_green")),
            float(match.group("secondary_blue")),
        ],
        "tertiary_color": [
            float(match.group("tertiary_red")),
            float(match.group("tertiary_green")),
            float(match.group("tertiary_blue")),
        ],
        "text_color": [
            float(match.group("text_red")),
            float(match.group("text_green")),
            float(match.group("text_blue")),
        ],
        "high_contrast_color": [
            float(match.group("high_contrast_red")),
            float(match.group("high_contrast_green")),
            float(match.group("high_contrast_blue")),
        ],
        "output_type": match.group("output_type"),
        "output": output,
        "mutations": int(match.group("mutations")),
        "fallback": match.group("fallback"),
        "route": match.group("route"),
    }


def scene_script_vector_media_startup_metrics(
    preview_text: str,
) -> dict[str, Any]:
    """Parse the launch-frozen vector media route from the preview report."""

    lines = [
        line
        for line in preview_text.splitlines()
        if line.startswith(SCENE_SCRIPT_VECTOR_MEDIA_STARTUP_PREFIX)
    ]
    observations: list[dict[str, Any]] = []
    malformed_count = 0
    for line in lines:
        match = SCENE_SCRIPT_VECTOR_MEDIA_STARTUP_RE.fullmatch(line)
        if match is None:
            malformed_count += 1
            continue
        try:
            targets = json.loads(match.group("targets"))
        except (json.JSONDecodeError, TypeError):
            malformed_count += 1
            continue
        binding_count = int(match.group("bindings"))
        active_binding_count = int(match.group("active_bindings"))
        if (
            not isinstance(targets, list)
            or any(
                not isinstance(target, str) or not target
                for target in targets
            )
            or len(set(targets)) != len(targets)
            or binding_count != len(targets)
            or active_binding_count > binding_count
        ):
            malformed_count += 1
            continue
        observations.append({
            "schema": match.group("schema"),
            "bindings": binding_count,
            "active_bindings": active_binding_count,
            "route": match.group("route"),
            "fallback": match.group("fallback"),
            "reason": match.group("reason"),
            "profile": match.group("profile"),
            "input": match.group("input"),
            "live_provider": match.group("live_provider"),
            "targets": targets,
        })
    selected = observations[0] if len(observations) == 1 else {}
    return {
        "observation_count": len(lines),
        "malformed_observation_count": malformed_count,
        "schema": selected.get("schema"),
        "bindings": selected.get("bindings"),
        "active_bindings": selected.get("active_bindings"),
        "route": selected.get("route"),
        "fallback": selected.get("fallback"),
        "reason": selected.get("reason"),
        "profile": selected.get("profile"),
        "input": selected.get("input"),
        "live_provider": selected.get("live_provider"),
        "targets": selected.get("targets", []),
    }


def media_owner_output_metrics(
    vector_completions: list[dict[str, Any]],
    startup: dict[str, Any],
) -> list[dict[str, Any]]:
    """Select generic vector publications owned by the media route targets."""

    targets = startup.get("targets", [])
    outputs = []
    for completion in vector_completions:
        if any(_media_target_owns_output(target, completion) for target in targets):
            outputs.append(completion)
    return outputs


def _media_target_owns_output(
    target: Any,
    completion: dict[str, Any],
) -> bool:
    if not isinstance(target, str):
        return False
    effect_identity = (
        f"effectConstant(layerID: {completion.get('layer_id')}, "
        f"effectIndex: {completion.get('effect_index')}, "
        f"passIndex: {completion.get('pass_index')}, "
        f'name: "{completion.get("constant")}")'
    )
    if target == effect_identity:
        return True
    match = re.fullmatch(
        r"layer\(layerID: (?P<layer>\d+), field: (?:[^)]*\.)?(?P<field>[^.)]+)\)",
        target,
    )
    return (
        match is not None
        and int(match.group("layer")) == completion.get("layer_id")
        and match.group("field") == completion.get("field")
    )


def media_event_expectation_failures(
    sample: dict[str, Any],
    completions: list[dict[str, Any]],
    startup: dict[str, Any],
    owner_outputs: list[dict[str, Any]] | None = None,
) -> list[str]:
    """Validate optional matrix expectations without affecting legacy samples."""

    failures: list[str] = []
    count_key = "expected_media_color_callback_count"
    if count_key in sample:
        expected_count = sample[count_key]
        if (
            isinstance(expected_count, bool)
            or not isinstance(expected_count, int)
            or expected_count < 0
        ):
            failures.append("invalid expected media color callback count")
        elif len(completions) != expected_count:
            failures.append("media color callback count mismatch")

    callbacks_key = "expected_media_color_callbacks"
    if callbacks_key in sample:
        expected_callbacks = sample[callbacks_key]
        normalized_callbacks = _normalized_callback_expectations(
            expected_callbacks
        )
        if normalized_callbacks is None:
            failures.append("invalid expected media color callbacks")
        elif not _callbacks_match(normalized_callbacks, completions):
            failures.append("media color callbacks mismatch")

    startup_key = "expected_scene_script_vector_media_startup"
    if startup_key in sample:
        failures.extend(_startup_expectation_failures(sample[startup_key], startup))

    output_count_key = "expected_media_owner_output_count"
    if output_count_key in sample:
        expected_count = sample[output_count_key]
        if (
            isinstance(expected_count, bool)
            or not isinstance(expected_count, int)
            or expected_count < 0
        ):
            failures.append("invalid expected media owner output count")
        elif owner_outputs is None or len(owner_outputs) != expected_count:
            failures.append("media owner output count mismatch")
    return failures


def _normalized_callback_expectations(
    value: Any,
) -> list[dict[str, Any]] | None:
    if not isinstance(value, list):
        return None
    normalized: list[dict[str, Any]] = []
    allowed_fields = (
        MEDIA_COLOR_EXPECTATION_COMMON_REQUIRED_FIELDS
        | MEDIA_COLOR_EXPECTATION_EFFECT_IDENTITY_FIELDS
        | MEDIA_COLOR_EXPECTATION_LAYER_IDENTITY_FIELDS
        | MEDIA_COLOR_EXPECTATION_OPTIONAL_FIELDS
    )
    for callback in value:
        if not isinstance(callback, dict):
            return None
        fields = set(callback)
        if (
            not MEDIA_COLOR_EXPECTATION_COMMON_REQUIRED_FIELDS.issubset(fields)
            or not fields.issubset(allowed_fields)
        ):
            return None
        is_layer = callback.get("target_kind") == "layer"
        required_identity = (
            MEDIA_COLOR_EXPECTATION_LAYER_IDENTITY_FIELDS
            if is_layer else MEDIA_COLOR_EXPECTATION_EFFECT_IDENTITY_FIELDS
        )
        if not required_identity.issubset(fields):
            return None
        identity_values = [callback["layer_id"]]
        if not is_layer:
            identity_values.extend([
                callback["effect_index"],
                callback["pass_index"],
            ])
        if any(
            isinstance(member, bool)
            or not isinstance(member, int)
            or member < 0
            for member in identity_values
        ):
            return None
        generation = callback["generation"]
        if (
            isinstance(generation, bool)
            or not isinstance(generation, int)
            or generation <= 0
            or not isinstance(callback["has_thumbnail"], bool)
            or not isinstance(callback["route"], str)
            or not callback["route"]
        ):
            return None
        if is_layer:
            if callback.get("field") != "color":
                return None
        elif (
            not isinstance(callback.get("constant"), str)
            or not callback["constant"]
            or callback.get("target_kind") not in (None, "effectConstant")
        ):
            return None
        current = dict(callback)
        for field in MEDIA_COLOR_FIELDS:
            color = _normalized_finite_vector(callback[field], count=3)
            if color is None or any(not 0 <= component <= 1 for component in color):
                return None
            current[field] = color
        if "fallback" in current and (
            not isinstance(current["fallback"], str) or not current["fallback"]
        ):
            return None
        if "mutations" in current and (
            isinstance(current["mutations"], bool)
            or not isinstance(current["mutations"], int)
            or current["mutations"] < 0
        ):
            return None
        if "output_type" in current and current["output_type"] not in {
            "vector2",
            "vector3",
        }:
            return None
        if "output" in current:
            output_count = 2 if current.get("output_type") == "vector2" else 3
            output = _normalized_finite_vector(current["output"], output_count)
            if output is None:
                return None
            current["output"] = output
        normalized.append(current)
    return normalized


def _normalized_finite_vector(value: Any, count: int) -> list[float] | None:
    if (
        not isinstance(value, list)
        or len(value) != count
        or any(
            isinstance(component, bool)
            or not isinstance(component, (int, float))
            or not math.isfinite(component)
            for component in value
        )
    ):
        return None
    return [float(component) for component in value]


def _callbacks_match(
    expected: list[dict[str, Any]],
    actual: list[dict[str, Any]],
) -> bool:
    if len(expected) != len(actual):
        return False
    expected_sorted = sorted(expected, key=_callback_identity)
    actual_sorted = sorted(actual, key=_callback_identity)
    return all(
        all(
            key in observed and _expectation_value_matches(value, observed[key])
            for key, value in wanted.items()
        )
        for wanted, observed in zip(expected_sorted, actual_sorted, strict=True)
    )


def _callback_identity(value: dict[str, Any]) -> tuple[Any, ...]:
    return (
        value.get("layer_id"),
        value.get("target_kind", "effectConstant"),
        value.get("effect_index"),
        value.get("pass_index"),
        value.get("constant"),
        value.get("field"),
        value.get("generation"),
    )


def _expectation_value_matches(expected: Any, actual: Any) -> bool:
    if isinstance(expected, float):
        return (
            isinstance(actual, (int, float))
            and not isinstance(actual, bool)
            and math.isclose(expected, float(actual), rel_tol=1e-8, abs_tol=1e-8)
        )
    if isinstance(expected, list):
        return (
            isinstance(actual, list)
            and len(expected) == len(actual)
            and all(
                _expectation_value_matches(wanted, observed)
                for wanted, observed in zip(expected, actual, strict=True)
            )
        )
    return expected == actual


def _startup_expectation_failures(
    expected: Any,
    actual: dict[str, Any],
) -> list[str]:
    if (
        not isinstance(expected, dict)
        or not {"route", "reason", "targets"}.issubset(expected)
        or not set(expected).issubset(SCENE_SCRIPT_VECTOR_MEDIA_STARTUP_FIELDS)
        or not isinstance(expected["targets"], list)
        or any(
            not isinstance(target, str) or not target
            for target in expected["targets"]
        )
        or len(set(expected["targets"])) != len(expected["targets"])
    ):
        return ["invalid SceneScript vector media startup expectation"]
    for field, value in expected.items():
        if field in {"bindings", "active_bindings"}:
            if isinstance(value, bool) or not isinstance(value, int) or value < 0:
                return ["invalid SceneScript vector media startup expectation"]
        elif field != "targets" and (
            not isinstance(value, str) or not value
        ):
            return ["invalid SceneScript vector media startup expectation"]
    if (
        actual.get("observation_count") != 1
        or actual.get("malformed_observation_count") != 0
    ):
        return ["SceneScript vector media startup observation mismatch"]
    failures = []
    for field, value in expected.items():
        observed = actual.get(field)
        if field == "targets":
            if sorted(value) != sorted(observed or []):
                failures.append("SceneScript vector media startup targets mismatch")
        elif observed != value:
            failures.append(f"SceneScript vector media startup {field} mismatch")
    return failures


def append_media_thumbnail_argument(
    command: list[str],
    media_thumbnail_path: Any,
    runtime_sample: Path,
    failures: list[str],
    *,
    primary_color: Any = None,
    secondary_color: Any = None,
    tertiary_color: Any = None,
    text_color: Any = None,
    high_contrast_color: Any = None,
    playback_state: Any = None,
) -> None:
    """Append a validated media-thumbnail event scoped to an isolated sample."""

    if media_thumbnail_path is None:
        if (
            primary_color is not None
            or secondary_color is not None
            or tertiary_color is not None
            or text_color is not None
            or high_contrast_color is not None
            or playback_state is not None
        ):
            failures.append(
                "media thumbnail event requires isolated media thumbnail path"
            )
        return

    media_thumbnail = Path(str(media_thumbnail_path))
    if (
        media_thumbnail.is_absolute()
        or ".." in media_thumbnail.parts
        or media_thumbnail.suffix.lower() not in {".png", ".jpg", ".jpeg"}
        or not (runtime_sample / media_thumbnail).is_file()
    ):
        failures.append("invalid isolated media thumbnail path")
        return

    def normalized_palette_color(
        value: Any,
        member: str,
    ) -> list[float] | None:
        if value is None:
            return None
        if (
            not isinstance(value, list)
            or len(value) != 3
            or any(
                isinstance(component, bool)
                or not isinstance(component, (int, float))
                or not math.isfinite(component)
                or not 0 <= component <= 1
                for component in value
            )
        ):
            failures.append(f"invalid media thumbnail {member} color")
            return None
        return [float(component) for component in value]

    normalized_primary = normalized_palette_color(primary_color, "primary")
    if primary_color is not None and normalized_primary is None:
        return
    normalized_secondary = normalized_palette_color(secondary_color, "secondary")
    if secondary_color is not None and normalized_secondary is None:
        return
    normalized_tertiary = normalized_palette_color(tertiary_color, "tertiary")
    if tertiary_color is not None and normalized_tertiary is None:
        return
    normalized_text = normalized_palette_color(text_color, "text")
    if text_color is not None and normalized_text is None:
        return
    normalized_high_contrast = normalized_palette_color(
        high_contrast_color,
        "high contrast",
    )
    if high_contrast_color is not None and normalized_high_contrast is None:
        return
    if playback_state is not None and (
        isinstance(playback_state, bool)
        or not isinstance(playback_state, int)
        or not 0 <= playback_state <= 2
    ):
        failures.append("invalid media thumbnail playback state")
        return

    arguments = [
        "--mwx-debug-scene-media-thumbnail",
        str(media_thumbnail),
    ]
    palette_arguments = (
        (
            normalized_primary,
            "--mwx-debug-scene-media-primary-color-json",
        ),
        (
            normalized_secondary,
            "--mwx-debug-scene-media-secondary-color-json",
        ),
        (
            normalized_tertiary,
            "--mwx-debug-scene-media-tertiary-color-json",
        ),
        (
            normalized_text,
            "--mwx-debug-scene-media-text-color-json",
        ),
        (
            normalized_high_contrast,
            "--mwx-debug-scene-media-high-contrast-color-json",
        ),
    )
    for color, flag in palette_arguments:
        if color is not None:
            arguments.extend([
                flag,
                json.dumps(color, separators=(",", ":")),
            ])
    if playback_state is not None:
        arguments.extend([
            "--mwx-debug-scene-media-playback-state",
            str(playback_state),
        ])
    command.extend(arguments)
