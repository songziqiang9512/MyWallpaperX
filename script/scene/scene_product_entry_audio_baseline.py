"""Contracts for the Scene product-entry audio corpus baseline.

This module is intentionally not a second command-line tool. The existing
``scene_wallpaper_benchmark.py`` owns staging, execution, cleanup, and report
publication; these helpers only keep the audio-corpus source and S3 result
classification out of that already-large driver.
"""

from __future__ import annotations

import base64
import binascii
import json
import math
import re
import sys
from collections import Counter
from pathlib import Path
from typing import Any


SCRIPT_DIRECTORY = Path(__file__).resolve().parent
if str(SCRIPT_DIRECTORY) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIRECTORY))

from scene_capability_census_io import is_sample_directory_name, validated_sample_id


PRODUCT_ENTRY_AUDIO_MODE = "product-entry-audio-baseline"
PRODUCT_ENTRY_RECORD_ID = "debug-scene-daemon-client"
PRIVATE_DEFAULTS_PREFIX = "com.songziqiang.MyWallpaperX.Debug.AudioCorpus."

_MATERIAL_AUDIO_CONSUMPTION_PREFIX = (
    "MWX typed input consumption: channel=audio-spectrum "
    "consumer=material-uniform "
)
_MATERIAL_AUDIO_CONSUMPTION_RE = re.compile(
    re.escape(_MATERIAL_AUDIO_CONSUMPTION_PREFIX)
    + r"layer=(?P<layer>-?\d+) effect=(?P<effect>-?\d+) "
    + r"descriptor=(?P<descriptor>\S+) node=(?P<node>\d+) "
    + r"uniform=g_AudioSpectrum(?P<uniform_count>16|32|64)"
    + r"(?P<uniform_side>Left|Right) side=(?P<side>left|right) "
    + r"count=(?P<count>16|32|64) frame=(?P<frame>\d+) "
    + r"generation=(?P<generation>\d+) "
    + r"state=(?P<state>silent|nonzero) nonZero=(?P<nonzero>\d+) "
    + r"first=(?P<first>\S+) peak=(?P<peak>\S+)"
)
_SCENESCRIPT_AUDIO_VALUE_PREFIX = "callback=audioValuePublished type="
_SCENESCRIPT_AUDIO_VALUE_RE = re.compile(
    r"MWX SceneScript VM: target=(?P<target>.*?) "
    r"callback=audioValuePublished "
    r"type=(?P<type>bool|scalar|vector2|vector3) "
    r"generation=(?P<generation>\d+) .*? route=(?P<route>\S+)"
)
_SCENESCRIPT_EFFECT_TARGET_RE = re.compile(
    r"effectConstant\(layerID: (?P<layer>-?\d+), "
    r"effectIndex: (?P<effect>\d+), passIndex: (?P<pass>\d+), "
    r'name: "(?P<name>(?:\\.|[^"\\])*)"\)'
)
_SCENESCRIPT_FIELD_TARGET_RE = re.compile(
    r"(?P<target_kind>layer|particle|text)\(layerID: (?P<layer>-?\d+), "
    r"field: MyWallpaperX\.SceneDynamic(?P<field_owner>Layer|Particle|Text)Field\."
    r"(?P<field>[A-Za-z][A-Za-z0-9]*)\)"
)
_SCENESCRIPT_FIELD_OWNER_BY_KIND = {
    "layer": "Layer",
    "particle": "Particle",
    "text": "Text",
}
_PARTICLE_AUDIO_CONSUMPTION_PREFIX = (
    "MWX particle audio: consumer=particle-component "
)
_PARTICLE_AUDIO_CONSUMPTION_RE = re.compile(
    re.escape(_PARTICLE_AUDIO_CONSUMPTION_PREFIX)
    + r"layer=(?P<layer>-?\d+) "
    + r"pathBase64=(?P<path_base64>[A-Za-z0-9+/]*={0,2}) "
    + r"component=(?P<component>emitter|initializer|operator) "
    + r"index=(?P<index>\d+) generation=(?P<generation>\d+) "
    + r"channel=(?P<channel>[123]) "
    + r"frequencyStart=(?P<frequency_start>\d+) "
    + r"frequencyEnd=(?P<frequency_end>\d+) "
    + r"selectedNonZero=(?P<selected_nonzero>\d+) "
    + r"route=(?P<route>\S+)$",
    re.MULTILINE,
)


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
            or not is_sample_directory_name(value)
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


def reconcile_no_demand_declarations(
    sample_ids: list[str],
    audio_occurrences: list[dict[str, Any]],
) -> dict[str, Any]:
    """Classify declaration-only reasons behind a runtime no-demand set.

    This is deliberately a factual join, not an acceptance result. It only
    distinguishes authored activation from dormant shader schema or a missing
    particle audio mode; runtime execution, visual output, and parity remain
    separate evidence.
    """
    if (
        not sample_ids
        or any(
            not isinstance(value, str)
            or not is_sample_directory_name(value)
            for value in sample_ids
        )
        or sample_ids != sorted(sample_ids)
        or len(sample_ids) != len(set(sample_ids))
    ):
        raise ValueError(
            "no-demand sample identities must be unique sorted sample ids"
        )
    if not isinstance(audio_occurrences, list) or any(
        not isinstance(value, dict) for value in audio_occurrences
    ):
        raise ValueError("audio declarations must be a list of objects")

    occurrence_ids: set[str] = set()
    relations_by_sample: dict[str, list[dict[str, Any]]] = {
        sample_id: [] for sample_id in sample_ids
    }
    for occurrence in audio_occurrences:
        occurrence_id = occurrence.get("occurrence_id")
        if not isinstance(occurrence_id, str) or not occurrence_id:
            raise ValueError("audio declaration occurrence identity is missing")
        if occurrence_id in occurrence_ids:
            raise ValueError(
                f"duplicate audio declaration occurrence identity: {occurrence_id}"
            )
        occurrence_ids.add(occurrence_id)
        if occurrence.get("domain") != "audio-declaration":
            raise ValueError("non-audio declaration entered no-demand reconciliation")
        location = occurrence.get("location")
        sample_id = location.get("sample_id") if isinstance(location, dict) else None
        if sample_id not in relations_by_sample:
            continue
        kind = occurrence.get("kind")
        if kind not in {"project-support-enabled", "project-support-invalid"}:
            relations_by_sample[sample_id].append(occurrence)

    categories: dict[str, list[str]] = {
        "material-host-spectrum-not-authored": [],
        "particle-audio-mode-missing": [],
        "unresolved": [],
    }

    def is_preprocessor_only_material_schema(value: dict[str, Any]) -> bool:
        abi_states = value.get("source_abi_state_counts")
        return (
            value.get("kind") == "material-host-spectrum"
            and value.get("activation_state") == "not-authored"
            and value.get("source_declares_audio_processing_combo") is True
            and value.get("source_exact_resolutions") == []
            and isinstance(abi_states, dict)
            and set(abi_states) == {"preprocessor-conditioned"}
            and type(abi_states["preprocessor-conditioned"]) is int
            and abi_states["preprocessor-conditioned"] > 0
        )

    def is_missing_mode_particle_schema(value: dict[str, Any]) -> bool:
        parameter_keys = value.get("audio_parameter_keys")
        return (
            value.get("kind") == "particle-audio-response"
            and value.get("activation_state") == "missing-mode"
            and isinstance(parameter_keys, list)
            and bool(parameter_keys)
            and all(
                isinstance(key, str)
                and key.casefold().startswith("audioprocessing")
                for key in parameter_keys
            )
            and "audioprocessingmode" not in {
                key.casefold() for key in parameter_keys
            }
        )

    occurrence_counts = Counter()
    for sample_id in sample_ids:
        relations = relations_by_sample[sample_id]
        if not relations:
            raise ValueError(
                f"no audio relationship declaration for sample: {sample_id}"
            )
        if all(is_preprocessor_only_material_schema(value) for value in relations):
            category = "material-host-spectrum-not-authored"
        elif all(is_missing_mode_particle_schema(value) for value in relations):
            category = "particle-audio-mode-missing"
        else:
            category = "unresolved"
        categories[category].append(sample_id)
        occurrence_counts[category] += len(relations)

    return {
        "schema_version": 1,
        "sample_count": len(sample_ids),
        "categories": {
            category: {
                "sample_count": len(values),
                "sample_ids": values,
                "declaration_occurrence_count": occurrence_counts[category],
            }
            for category, values in categories.items()
        },
        "unresolved_sample_count": len(categories["unresolved"]),
        "unresolved_sample_ids": categories["unresolved"],
        "evidence_ceiling": "declaration-reconciliation-only",
        "runtime_validated": False,
        "visual_validated": False,
    }


def inventory_saved_audio_consumer_events(
    sample_ids: list[str],
    log_text_by_sample: dict[str, str],
) -> dict[str, Any]:
    """Inventory generic non-silent consumer events in saved product logs.

    The caller owns report/app/log identity and must supply only samples whose
    capture publication was independently accepted. This join raises the
    evidence ceiling only when the existing renderer, SceneScript owner, or a
    committed particle component logged a non-silent consumer event. It never
    infers particle audio execution from scene-level demand, and it never
    upgrades an event to visual response or official parity.
    """
    if (
        not sample_ids
        or any(
            not isinstance(value, str)
            or not is_sample_directory_name(value)
            for value in sample_ids
        )
        or sample_ids != sorted(sample_ids)
        or len(sample_ids) != len(set(sample_ids))
    ):
        raise ValueError(
            "audio consumer sample identities must be unique sorted sample ids"
        )
    if not isinstance(log_text_by_sample, dict) or set(log_text_by_sample) != set(
        sample_ids
    ):
        raise ValueError("audio consumer log identities do not conserve the sample set")
    if any(type(value) is not str for value in log_text_by_sample.values()):
        raise ValueError("audio consumer logs must be text")

    rows: list[dict[str, Any]] = []
    material_resolution_consumer_counts: Counter[int] = Counter()
    material_resolution_sample_ids: dict[int, list[str]] = {
        16: [], 32: [], 64: [],
    }
    material_side_profile_counts: Counter[str] = Counter()
    script_target_kind_counts: Counter[str] = Counter()
    script_target_type_counts: Counter[str] = Counter()
    particle_component_kind_counts: Counter[str] = Counter()

    for sample_id in sample_ids:
        log_text = log_text_by_sample[sample_id]
        material_matches = list(_MATERIAL_AUDIO_CONSUMPTION_RE.finditer(log_text))
        if log_text.count(_MATERIAL_AUDIO_CONSUMPTION_PREFIX) != len(material_matches):
            raise ValueError(
                f"malformed material audio consumer event for sample: {sample_id}"
            )
        material_consumers: dict[
            tuple[int, int, str, int, int], dict[str, Any]
        ] = {}
        for match in material_matches:
            value = match.groupdict()
            count = int(value["count"])
            side = value["side"]
            if (
                value["uniform_count"] != value["count"]
                or value["uniform_side"].casefold() != side
            ):
                raise ValueError(
                    f"material audio consumer identity mismatch for sample: {sample_id}"
                )
            try:
                first = float(value["first"])
                peak = float(value["peak"])
            except (OverflowError, ValueError) as error:
                raise ValueError(
                    f"material audio consumer value is malformed for sample: {sample_id}"
                ) from error
            if not math.isfinite(first) or not math.isfinite(peak):
                raise ValueError(
                    f"material audio consumer value is non-finite for sample: {sample_id}"
                )
            state = value["state"]
            generation = int(value["generation"])
            nonzero = int(value["nonzero"])
            if state == "silent":
                if nonzero != 0 or peak != 0:
                    raise ValueError(
                        f"silent material audio event is inconsistent for sample: {sample_id}"
                    )
                continue
            if generation <= 0 or not 1 <= nonzero <= count or peak <= 0:
                raise ValueError(
                    f"non-silent material audio event is inconsistent for sample: {sample_id}"
                )
            identity = (
                int(value["layer"]),
                int(value["effect"]),
                value["descriptor"],
                int(value["node"]),
                count,
            )
            consumer = material_consumers.setdefault(identity, {
                "layer_id": identity[0],
                "effect_index": identity[1],
                "descriptor": identity[2],
                "node_index": identity[3],
                "resolution": identity[4],
                "nonzero_sides": set(),
                "first_nonzero_generation_by_side": {},
            })
            consumer["nonzero_sides"].add(side)
            previous = consumer["first_nonzero_generation_by_side"].get(side)
            consumer["first_nonzero_generation_by_side"][side] = (
                generation if previous is None else min(previous, generation)
            )

        material_rows: list[dict[str, Any]] = []
        material_resolutions: set[int] = set()
        for identity in sorted(material_consumers):
            consumer = material_consumers[identity]
            sides = sorted(consumer.pop("nonzero_sides"))
            consumer["nonzero_sides"] = sides
            consumer["first_nonzero_generation_by_side"] = dict(sorted(
                consumer["first_nonzero_generation_by_side"].items()
            ))
            material_rows.append(consumer)
            resolution = int(consumer["resolution"])
            material_resolutions.add(resolution)
            material_resolution_consumer_counts[resolution] += 1
            material_side_profile_counts["+".join(sides)] += 1
        for resolution in sorted(material_resolutions):
            material_resolution_sample_ids[resolution].append(sample_id)

        script_matches = list(_SCENESCRIPT_AUDIO_VALUE_RE.finditer(log_text))
        if log_text.count(_SCENESCRIPT_AUDIO_VALUE_PREFIX) != len(script_matches):
            raise ValueError(
                f"malformed SceneScript audio consumer event for sample: {sample_id}"
            )
        script_consumers: dict[str, dict[str, Any]] = {}
        for match in script_matches:
            value = match.groupdict()
            generation = int(value["generation"])
            if generation <= 0 or value["route"] != "generic-only":
                raise ValueError(
                    f"SceneScript audio consumer identity is invalid for sample: {sample_id}"
                )
            target = value["target"]
            effect_target = _SCENESCRIPT_EFFECT_TARGET_RE.fullmatch(target)
            field_target = _SCENESCRIPT_FIELD_TARGET_RE.fullmatch(target)
            if effect_target is not None:
                target_kind = "effectConstant"
            elif field_target is not None:
                target_kind = str(field_target["target_kind"])
                if (
                    _SCENESCRIPT_FIELD_OWNER_BY_KIND[target_kind]
                    != field_target["field_owner"]
                ):
                    raise ValueError(
                        "SceneScript audio consumer field owner is invalid for "
                        f"sample: {sample_id}"
                    )
            else:
                raise ValueError(
                    f"SceneScript audio consumer target is invalid for sample: {sample_id}"
                )
            consumer = script_consumers.get(target)
            if consumer is None:
                script_consumers[target] = {
                    "target": target,
                    "target_kind": target_kind,
                    "value_type": value["type"],
                    "first_nonzero_generation": generation,
                }
            else:
                if consumer["value_type"] != value["type"]:
                    raise ValueError(
                        "SceneScript audio consumer value type changed for "
                        f"sample: {sample_id}"
                    )
                consumer["first_nonzero_generation"] = min(
                    int(consumer["first_nonzero_generation"]), generation
                )
        script_rows = [script_consumers[key] for key in sorted(script_consumers)]
        for consumer in script_rows:
            script_target_kind_counts[str(consumer["target_kind"])] += 1
            script_target_type_counts[str(consumer["value_type"])] += 1

        particle_matches = list(_PARTICLE_AUDIO_CONSUMPTION_RE.finditer(log_text))
        if log_text.count(_PARTICLE_AUDIO_CONSUMPTION_PREFIX) != len(
            particle_matches
        ):
            raise ValueError(
                f"malformed particle audio consumer event for sample: {sample_id}"
            )
        particle_consumers: dict[
            tuple[int, str, str, int], dict[str, Any]
        ] = {}
        for match in particle_matches:
            value = match.groupdict()
            try:
                path = base64.b64decode(
                    value["path_base64"], validate=True
                ).decode("utf-8")
            except (binascii.Error, UnicodeDecodeError) as error:
                raise ValueError(
                    f"particle audio consumer path is invalid for sample: {sample_id}"
                ) from error
            channel = int(value["channel"])
            frequency_start = int(value["frequency_start"])
            frequency_end = int(value["frequency_end"])
            selected_nonzero = int(value["selected_nonzero"])
            generation = int(value["generation"])
            selected_value_count = (
                frequency_end - frequency_start + 1
            ) * (2 if channel == 3 else 1)
            if (
                not path
                or path != path.strip()
                or any(ord(character) < 32 or ord(character) == 127 for character in path)
                or value["route"] != "generic-only"
                or generation <= 0
                or not 0 <= frequency_start <= frequency_end < 16
                or not 1 <= selected_nonzero <= selected_value_count
            ):
                raise ValueError(
                    f"particle audio consumer identity is invalid for sample: {sample_id}"
                )
            identity = (
                int(value["layer"]),
                path,
                value["component"],
                int(value["index"]),
            )
            consumer = particle_consumers.get(identity)
            configuration = {
                "layer_id": identity[0],
                "particle_path": identity[1],
                "component_kind": identity[2],
                "component_index": identity[3],
                "channel": channel,
                "frequency_start": frequency_start,
                "frequency_end": frequency_end,
            }
            if consumer is None:
                particle_consumers[identity] = {
                    **configuration,
                    "first_nonzero_generation": generation,
                    "selected_nonzero_input_count": selected_nonzero,
                }
            else:
                if any(consumer[key] != expected for key, expected in configuration.items()):
                    raise ValueError(
                        "particle audio consumer configuration changed for "
                        f"sample: {sample_id}"
                    )
                consumer["first_nonzero_generation"] = min(
                    int(consumer["first_nonzero_generation"]), generation
                )
                consumer["selected_nonzero_input_count"] = max(
                    int(consumer["selected_nonzero_input_count"]), selected_nonzero
                )
        particle_rows = [
            particle_consumers[key] for key in sorted(particle_consumers)
        ]
        for consumer in particle_rows:
            particle_component_kind_counts[str(consumer["component_kind"])] += 1

        has_material = bool(material_rows)
        has_script = bool(script_rows)
        has_particle = bool(particle_rows)
        if has_material and has_script and has_particle:
            event_class = "material-scenescript-and-particle-consumer-events"
        elif has_material and has_particle:
            event_class = "material-and-particle-consumer-events"
        elif has_script and has_particle:
            event_class = "scenescript-and-particle-consumer-events"
        elif has_material and has_script:
            event_class = "material-and-scenescript-consumer-events"
        elif has_material:
            event_class = "material-consumer-events"
        elif has_script:
            event_class = "scenescript-consumer-events"
        elif has_particle:
            event_class = "particle-consumer-events"
        else:
            event_class = "no-consumer-event-in-saved-log"
        rows.append({
            "sample_id": sample_id,
            "event_class": event_class,
            "consumer_event_executed": has_material or has_script or has_particle,
            "material_uniform_consumers": material_rows,
            "material_resolutions": sorted(material_resolutions),
            "scenescript_consumers": script_rows,
            "scenescript_target_kinds": sorted({
                str(value["target_kind"]) for value in script_rows
            }),
            "particle_component_consumers": particle_rows,
            "particle_component_kinds": sorted({
                str(value["component_kind"]) for value in particle_rows
            }),
            "evidence_ceiling": (
                "S3-saved-log-consumer-event"
                if has_material or has_script or has_particle
                else "S3-capture-publication-only"
            ),
            "visual_validated": False,
        })

    event_classes = Counter(str(row["event_class"]) for row in rows)
    consumer_event_sample_ids = [
        str(row["sample_id"]) for row in rows if row["consumer_event_executed"]
    ]
    no_consumer_event_sample_ids = [
        str(row["sample_id"]) for row in rows if not row["consumer_event_executed"]
    ]
    return {
        "schema_version": 2,
        "sample_count": len(sample_ids),
        "consumer_event_sample_count": len(consumer_event_sample_ids),
        "consumer_event_sample_ids": consumer_event_sample_ids,
        "no_consumer_event_sample_count": len(no_consumer_event_sample_ids),
        "no_consumer_event_sample_ids": no_consumer_event_sample_ids,
        "event_class_counts": dict(sorted(event_classes.items())),
        "material_uniform_sample_count": sum(
            bool(row["material_uniform_consumers"]) for row in rows
        ),
        "material_uniform_consumer_count": sum(
            len(row["material_uniform_consumers"]) for row in rows
        ),
        "material_resolution_consumer_counts": {
            str(key): material_resolution_consumer_counts[key]
            for key in (16, 32, 64)
        },
        "material_resolution_sample_ids": {
            str(key): material_resolution_sample_ids[key]
            for key in (16, 32, 64)
        },
        "material_side_profile_counts": dict(sorted(
            material_side_profile_counts.items()
        )),
        "scenescript_sample_count": sum(
            bool(row["scenescript_consumers"]) for row in rows
        ),
        "scenescript_target_count": sum(
            len(row["scenescript_consumers"]) for row in rows
        ),
        "scenescript_target_kind_counts": dict(sorted(
            script_target_kind_counts.items()
        )),
        "scenescript_target_type_counts": dict(sorted(
            script_target_type_counts.items()
        )),
        "particle_component_sample_count": sum(
            bool(row["particle_component_consumers"]) for row in rows
        ),
        "particle_component_consumer_count": sum(
            len(row["particle_component_consumers"]) for row in rows
        ),
        "particle_component_kind_counts": dict(sorted(
            particle_component_kind_counts.items()
        )),
        "samples": rows,
        "evidence_ceiling": "S3-saved-log-consumer-event-inventory",
        "particle_component_execution_validated": any(
            row["particle_component_consumers"] for row in rows
        ),
        "visual_validated": False,
    }


def private_defaults_suite(sample_id: str) -> str:
    validated_sample_id(sample_id, context="product-entry audio sample ID")
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
