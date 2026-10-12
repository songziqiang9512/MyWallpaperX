"""Parse typed SceneScript, property and media publication identities."""

from __future__ import annotations

import re
from scene_wallpaper_performance import FLOAT_PATTERN
from typing import Any


TEXT_SCRIPT_BINDING_COUNT_RE = re.compile(
    r"^textScriptBindingCount: (?P<count>\d+)$",
    re.MULTILINE,
)

TEXT_SCRIPT_DIAGNOSTIC_COUNT_RE = re.compile(
    r"^textScriptDiagnosticCount: (?P<count>\d+)$",
    re.MULTILINE,
)

TEXT_SCRIPT_BINDING_RE = re.compile(
    r"^textScript layer (?P<id>\d+) content: profile=(?P<profile>\S+) "
    r"value@fixture=(?P<value>.+)$",
    re.MULTILINE,
)

SCENE_SCRIPT_SCALAR_BINDING_COUNT_RE = re.compile(
    r"^scene script VM: schema=quickjs-ng-(?:scalar-v1|typed-v2) "
    r"bindings=(?P<count>\d+)(?: (?:vec3Bindings|vectorBindings)="
    r"(?P<vector_count>\d+))?(?: stringBindings=\d+)? "
    r"targets=(?P<targets>\d+) "
    r"route=(?P<route>\S+) fallback=(?P<fallback>\S+)$",
    re.MULTILINE,
)

SCENE_SCRIPT_VEC3_COMPLETION_RE = re.compile(
    r"MWX SceneScript VM: target=(?P<target_kind>layer|text)\(layerID: (?P<layer>\d+), "
    r"field: [^)]*\.(?P<field>origin|scale|angles|color)\) callback=completed "
    r"type=vector3 input=(?P<input>vector3\([^)]*\)) "
    r"output=(?P<output>vector3\([^)]*\)).* route=(?P<route>\S+)"
)

TEXT_SCRIPT_COMPLETION_RE = re.compile(
    r"MWX SceneScript VM: target=text\(layerID: (?P<layer>\d+), "
    r"field: [^)]*\.content\) callback=completed"
)

SCENE_SCRIPT_EFFECT_VECTOR_COMPLETION_RE = re.compile(
    r"MWX SceneScript VM: target=effectConstant\(layerID: (?P<layer>\d+), "
    r"effectIndex: (?P<effect>\d+), passIndex: (?P<pass>\d+), "
    r'name: "(?P<constant>[^"]+)"\) callback=completed '
    r"type=(?P<type>vector[23]) input=(?P<input>vector[23]\([^)]*\)) "
    r"output=(?P<output>vector[23]\([^)]*\)).* route=(?P<route>\S+)"
)

SCENE_SCRIPT_AUDIO_VECTOR_PUBLICATION_RE = re.compile(
    r"MWX SceneScript VM: target=effectConstant\(layerID: (?P<layer>\d+), "
    r"effectIndex: (?P<effect>\d+), passIndex: (?P<pass>\d+), "
    r'name: "(?P<constant>[^"]+)"\) callback=audioValuePublished '
    r"type=(?P<type>vector[23]) generation=(?P<generation>\d+) "
    r"input=(?P<input>vector[23]\([^)]*\)) "
    r"output=(?P<output>vector[23]\([^)]*\)) route=(?P<route>\S+)"
)

SCENE_SCRIPT_SCALAR_COMPLETION_RE = re.compile(
    r"MWX SceneScript VM: target=effectConstant\(layerID: (?P<layer>\d+), "
    r"effectIndex: (?P<effect>\d+), passIndex: (?P<pass>\d+), "
    r'name: "(?P<constant>[^"]+)"\) callback=completed '
    r"input=(?P<input>\S+) output=(?P<output>\S+) mutations=(?P<mutations>\d+) "
    r"mutationTargets=(?P<mutation_targets>\S*) route=(?P<route>\S+)"
)

SCENE_SCRIPT_OBJECT_SCALAR_COMPLETION_RE = re.compile(
    r"MWX SceneScript VM: target=(?P<kind>layer|text|particle)\(layerID: "
    r"(?P<layer>\d+), field: [^)]*\.(?P<field>alpha|pointSize|rate)\) "
    r"callback=completed input=(?P<input>\S+) output=(?P<output>\S+) "
    r"mutations=(?P<mutations>\d+) mutationTargets=(?P<mutation_targets>\S*) "
    r"route=(?P<route>\S+)"
)

SCENE_SCRIPT_AUDIO_SCALAR_PUBLICATION_RE = re.compile(
    r"MWX SceneScript VM: target=effectConstant\(layerID: (?P<layer>\d+), "
    r"effectIndex: (?P<effect>\d+), passIndex: (?P<pass>\d+), "
    r'name: "(?P<constant>[^"]+)"\) callback=audioValuePublished '
    r"type=scalar generation=(?P<generation>\d+) "
    r"input=(?P<input>\S+) output=(?P<output>\S+) route=(?P<route>\S+)"
)

TYPED_USER_PROPERTY_SCALAR_UNIFORM_PUBLICATION_RE = re.compile(
    r"MWX typed input publication: channel=user-property "
    r"consumer=material-uniform layer=(?P<layer>-?\d+) "
    r"effect=(?P<effect>-?\d+) descriptor=(?P<descriptor>\S+) "
    r"node=(?P<node>\d+) property=(?P<property>\S+) "
    r"pass=(?P<pass>\d+) constant=(?P<constant>\S+) "
    r"uniform=(?P<uniform>\S+) stage=(?P<stage>vertex|fragment|shared) "
    r"type=float frame=(?P<frame>\d+) generation=(?P<generation>\d+) "
    rf"value=(?P<value>{FLOAT_PATTERN})"
)

TYPED_USER_PROPERTY_SCALAR_SPLAT_UNIFORM_PUBLICATION_RE = re.compile(
    r"MWX typed input publication: channel=user-property "
    r"consumer=material-uniform layer=(?P<layer>-?\d+) "
    r"effect=(?P<effect>-?\d+) descriptor=(?P<descriptor>\S+) "
    r"node=(?P<node>\d+) property=(?P<property>\S+) "
    r"pass=(?P<pass>\d+) constant=(?P<constant>\S+) "
    r"uniform=(?P<uniform>\S+) stage=(?P<stage>vertex|fragment|shared) "
    r"type=float2-scalar-splat frame=(?P<frame>\d+) "
    r"generation=(?P<generation>\d+) "
    rf"value=(?P<x>{FLOAT_PATTERN}),(?P<y>{FLOAT_PATTERN})"
)

TYPED_USER_PROPERTY_BOOL_ACTIVATION_PUBLICATION_RE = re.compile(
    r"MWX typed input publication: channel=user-property "
    r"consumer=effect-activation layer=(?P<layer>-?\d+) "
    r"effect=(?P<effect>-?\d+) descriptor=(?P<descriptor>\S+) "
    r"property=(?P<property>\S+) type=bool frame=(?P<frame>\d+) "
    r"generation=(?P<generation>\d+) value=(?P<value>true|false) "
    r"decision=(?P<decision>active|inactive)"
)

MEDIA_THUMBNAIL_CURRENT_BINDING_COUNT_RE = re.compile(
    r"^mediaThumbnailCurrentBindingCount: (?P<count>\d+)$",
    re.MULTILINE,
)

MEDIA_THUMBNAIL_CURRENT_BINDING_LAYER_IDS_RE = re.compile(
    r"^mediaThumbnailCurrentBindingLayerIDs: (?P<ids>[\d,]*)$",
    re.MULTILINE,
)

MEDIA_THUMBNAIL_PREVIOUS_BINDING_COUNT_RE = re.compile(
    r"^mediaThumbnailPreviousBindingCount: (?P<count>\d+)$",
    re.MULTILINE,
)

MEDIA_THUMBNAIL_PREVIOUS_BINDING_LAYER_IDS_RE = re.compile(
    r"^mediaThumbnailPreviousBindingLayerIDs: (?P<ids>[\d,]*)$",
    re.MULTILINE,
)

MEDIA_THUMBNAIL_PENDING_RE = re.compile(
    r"media thumbnail store: phase=pending-last-ready "
    r"requestedGeneration=(?P<requested>\d+) "
    r"readyGeneration=(?P<ready>\d+) "
    r"(?:hasCurrent=(?P<legacy_current>true|false)|"
    r"hasColor=(?P<color>true|false) "
    r"hasPreserved=(?P<preserved>true|false))"
)

MEDIA_THUMBNAIL_READY_RE = re.compile(
    r"media thumbnail store: phase=ready generation=(?P<generation>\d+) "
    r"(?:hasCurrent=(?P<legacy_current>true|false)|"
    r"hasColor=(?P<color>true|false) "
    r"hasPreserved=(?P<preserved>true|false))"
)

MEDIA_THUMBNAIL_CLEAR_RE = re.compile(r"phase=media-thumbnail-cleared")

def text_script_runtime_metrics(preview_text: str, log_text: str = "") -> dict[str, Any]:
    # The preview helper emits summary counters, while the real SceneScript
    # host log is authoritative for completed callbacks.  Parse both so a
    # successful producer/consumer run is not reported as an empty binding
    # set merely because the preview subprocess omitted its summary.
    evidence_text = preview_text + "\n" + log_text
    binding_match = TEXT_SCRIPT_BINDING_COUNT_RE.search(evidence_text)
    diagnostic_match = TEXT_SCRIPT_DIAGNOSTIC_COUNT_RE.search(evidence_text)
    bindings = [
        {
            "layer_id": int(match.group("id")),
            "profile": match.group("profile"),
            "fixture_value": match.group("value"),
        }
        for match in TEXT_SCRIPT_BINDING_RE.finditer(evidence_text)
    ]
    if not bindings:
        completed_ids = sorted({
            int(match.group("layer"))
            for match in TEXT_SCRIPT_COMPLETION_RE.finditer(evidence_text)
        })
    else:
        completed_ids = sorted(binding["layer_id"] for binding in bindings)
    return {
        "binding_count": int(binding_match.group("count")) if binding_match else len(completed_ids),
        "diagnostic_count": (
            int(diagnostic_match.group("count")) if diagnostic_match else None
        ),
        "binding_layer_ids": completed_ids,
        "bindings": bindings,
    }

def scene_script_scalar_runtime_metrics(
    preview_text: str,
    log_text: str,
) -> dict[str, Any]:
    count_match = SCENE_SCRIPT_SCALAR_BINDING_COUNT_RE.search(preview_text)
    completions = [
        {
            "layer_id": int(match.group("layer")),
            "effect_index": int(match.group("effect")),
            "pass_index": int(match.group("pass")),
            "constant": match.group("constant"),
            "input": float(match.group("input")),
            "output": float(match.group("output")),
            "mutation_count": int(match.group("mutations")),
            "route": match.group("route"),
        }
        for match in SCENE_SCRIPT_SCALAR_COMPLETION_RE.finditer(log_text)
    ]
    completions.sort(key=lambda value: (
        value["layer_id"],
        value["effect_index"],
        value["pass_index"],
        value["constant"],
    ))
    object_scalar_completions = [
        {
            "layer_id": int(match.group("layer")),
            "target_kind": match.group("kind"),
            "field": match.group("field"),
            "input": float(match.group("input")),
            "output": float(match.group("output")),
            "mutation_count": int(match.group("mutations")),
            "route": match.group("route"),
        }
        for match in SCENE_SCRIPT_OBJECT_SCALAR_COMPLETION_RE.finditer(log_text)
    ]
    object_scalar_completions.sort(key=lambda value: (
        value["layer_id"], value["target_kind"], value["field"],
    ))
    audio_scalar_publications = [
        {
            "layer_id": int(match.group("layer")),
            "effect_index": int(match.group("effect")),
            "pass_index": int(match.group("pass")),
            "constant": match.group("constant"),
            "generation": int(match.group("generation")),
            "input": float(match.group("input")),
            "output": float(match.group("output")),
            "route": match.group("route"),
        }
        for match in SCENE_SCRIPT_AUDIO_SCALAR_PUBLICATION_RE.finditer(log_text)
    ]
    audio_scalar_publications.sort(key=lambda value: (
        value["layer_id"], value["effect_index"], value["pass_index"],
        value["constant"],
    ))
    vec3_completions = [
        {
            "layer_id": int(match.group("layer")),
            "target_kind": match.group("target_kind"),
            "field": match.group("field"),
            "input": match.group("input"),
            "output": match.group("output"),
            "route": match.group("route"),
        }
        for match in SCENE_SCRIPT_VEC3_COMPLETION_RE.finditer(log_text)
    ]
    vec3_completions.sort(key=lambda value: (
        value["layer_id"], value["target_kind"], value["field"],
    ))
    effect_vector_completions = [
        {
            "layer_id": int(match.group("layer")),
            "effect_index": int(match.group("effect")),
            "pass_index": int(match.group("pass")),
            "constant": match.group("constant"),
            "type": match.group("type"),
            "input": match.group("input"),
            "output": match.group("output"),
            "route": match.group("route"),
        }
        for match in SCENE_SCRIPT_EFFECT_VECTOR_COMPLETION_RE.finditer(log_text)
    ]
    effect_vector_completions.sort(key=lambda value: (
        value["layer_id"], value["effect_index"], value["pass_index"],
        value["constant"],
    ))
    audio_vector_publications = [
        {
            "layer_id": int(match.group("layer")),
            "effect_index": int(match.group("effect")),
            "pass_index": int(match.group("pass")),
            "constant": match.group("constant"),
            "type": match.group("type"),
            "generation": int(match.group("generation")),
            "input": match.group("input"),
            "output": match.group("output"),
            "route": match.group("route"),
        }
        for match in SCENE_SCRIPT_AUDIO_VECTOR_PUBLICATION_RE.finditer(log_text)
    ]
    audio_vector_publications.sort(key=lambda value: (
        value["layer_id"], value["effect_index"], value["pass_index"],
        value["constant"],
    ))
    return {
        "binding_count": int(count_match.group("count")) if count_match else None,
        "vector_binding_count": (
            int(count_match.group("vector_count"))
            if count_match and count_match.group("vector_count") is not None
            else None
        ),
        "vec3_binding_count": (
            int(count_match.group("vector_count"))
            if count_match and count_match.group("vector_count") is not None
            else None
        ),
        "target_count": int(count_match.group("targets")) if count_match else None,
        "route": count_match.group("route") if count_match else None,
        "fallback": count_match.group("fallback") if count_match else None,
        "completions": completions,
        "object_scalar_completions": object_scalar_completions,
        "audio_scalar_publications": audio_scalar_publications,
        "vec3_completions": vec3_completions,
        "effect_vector_completions": effect_vector_completions,
        "audio_vector_publications": audio_vector_publications,
        "bindings": [
            {
                "layer_id": completion["layer_id"],
                "effect_index": completion["effect_index"],
                "pass_index": completion["pass_index"],
                "constant": completion["constant"],
            }
            for completion in completions
        ],
    }

def typed_user_property_scalar_uniform_publications(
    log_text: str,
) -> list[dict[str, Any]]:
    publications = [
        {
            "layer_id": int(match.group("layer")),
            "effect_index": int(match.group("effect")),
            "descriptor_id": match.group("descriptor"),
            "node_index": int(match.group("node")),
            "property_key": match.group("property"),
            "pass_index": int(match.group("pass")),
            "constant": match.group("constant"),
            "uniform": match.group("uniform"),
            "stage": match.group("stage"),
            "type": "float",
            "frame": int(match.group("frame")),
            "generation": int(match.group("generation")),
            "value": float(match.group("value")),
        }
        for match in TYPED_USER_PROPERTY_SCALAR_UNIFORM_PUBLICATION_RE.finditer(
            log_text
        )
    ]
    publications.sort(key=lambda value: (
        value["layer_id"], value["effect_index"], value["node_index"],
        value["property_key"], value["uniform"], value["stage"],
    ))
    return publications

def typed_user_property_scalar_splat_uniform_publications(
    log_text: str,
) -> list[dict[str, Any]]:
    publications = [
        {
            "layer_id": int(match.group("layer")),
            "effect_index": int(match.group("effect")),
            "descriptor_id": match.group("descriptor"),
            "node_index": int(match.group("node")),
            "property_key": match.group("property"),
            "pass_index": int(match.group("pass")),
            "constant": match.group("constant"),
            "uniform": match.group("uniform"),
            "stage": match.group("stage"),
            "type": "float2",
            "source_type": "scalar",
            "projection": "isotropic-splat",
            "frame": int(match.group("frame")),
            "generation": int(match.group("generation")),
            "value": [float(match.group("x")), float(match.group("y"))],
        }
        for match in TYPED_USER_PROPERTY_SCALAR_SPLAT_UNIFORM_PUBLICATION_RE.finditer(
            log_text
        )
    ]
    publications.sort(key=lambda value: (
        value["layer_id"], value["effect_index"], value["node_index"],
        value["property_key"], value["uniform"], value["stage"],
    ))
    return publications

def typed_user_property_bool_activation_publications(
    log_text: str,
) -> list[dict[str, Any]]:
    publications = [
        {
            "layer_id": int(match.group("layer")),
            "effect_index": int(match.group("effect")),
            "descriptor_id": match.group("descriptor"),
            "property_key": match.group("property"),
            "type": "bool",
            "frame": int(match.group("frame")),
            "generation": int(match.group("generation")),
            "value": match.group("value") == "true",
            "decision": match.group("decision"),
        }
        for match in TYPED_USER_PROPERTY_BOOL_ACTIVATION_PUBLICATION_RE.finditer(
            log_text
        )
    ]
    publications.sort(key=lambda value: (
        value["layer_id"], value["effect_index"], value["property_key"],
    ))
    return publications

def media_thumbnail_runtime_metrics(preview_text: str) -> dict[str, Any]:
    count_match = MEDIA_THUMBNAIL_CURRENT_BINDING_COUNT_RE.search(preview_text)
    layer_ids_match = MEDIA_THUMBNAIL_CURRENT_BINDING_LAYER_IDS_RE.search(preview_text)
    previous_count_match = MEDIA_THUMBNAIL_PREVIOUS_BINDING_COUNT_RE.search(
        preview_text
    )
    previous_layer_ids_match = (
        MEDIA_THUMBNAIL_PREVIOUS_BINDING_LAYER_IDS_RE.search(preview_text)
    )
    layer_ids = []
    if layer_ids_match:
        layer_ids = [
            int(value)
            for value in layer_ids_match.group("ids").split(",")
            if value
        ]
    previous_layer_ids = []
    if previous_layer_ids_match:
        previous_layer_ids = [
            int(value)
            for value in previous_layer_ids_match.group("ids").split(",")
            if value
        ]
    return {
        "current_binding_count": (
            int(count_match.group("count")) if count_match else None
        ),
        "current_binding_layer_ids": layer_ids,
        "previous_binding_count": (
            int(previous_count_match.group("count"))
            if previous_count_match else None
        ),
        "previous_binding_layer_ids": previous_layer_ids,
    }

def media_thumbnail_store_metrics(log_text: str) -> dict[str, Any]:
    def representation_state(match: re.Match[str]) -> dict[str, bool]:
        legacy = match.group("legacy_current")
        if legacy is not None:
            return {"has_current": legacy == "true"}
        color = match.group("color") == "true"
        return {
            "has_current": color,
            "has_color": color,
            "has_preserved": match.group("preserved") == "true",
        }

    return {
        "pending_last_ready": [
            {
                "requested_generation": int(match.group("requested")),
                "ready_generation": int(match.group("ready")),
                **representation_state(match),
            }
            for match in MEDIA_THUMBNAIL_PENDING_RE.finditer(log_text)
        ],
        "ready_states": [
            {
                "generation": int(match.group("generation")),
                **representation_state(match),
            }
            for match in MEDIA_THUMBNAIL_READY_RE.finditer(log_text)
        ],
        "clear_count": len(MEDIA_THUMBNAIL_CLEAR_RE.findall(log_text)),
    }
