#!/usr/bin/env python3
"""Effect, material, shader, graph, and texture census for Scene samples."""

from __future__ import annotations

from collections import Counter
from pathlib import PurePosixPath
from typing import Any

from scene_capability_census_io import (
    ResolvedResource,
    SceneResourceView,
    canonical_sha256,
    normalize_path,
    parse_tex_summary,
)
from scene_capability_census_profiles import (
    ParameterProfiles,
    family_key,
    occurrence_id,
    profile_parameter_mapping,
    revision_key,
    safe_value_shape,
)


def effective_visibility(value: Any, parent_visible: bool = True) -> str:
    if not parent_visible:
        return "hidden"
    if value is False:
        return "hidden"
    if isinstance(value, dict):
        inner = value.get("value")
        if inner is False:
            return "hidden"
        if any(key in value for key in ("user", "script", "animation", "condition")):
            return "dynamic"
    return "visible"


def nested_visibility(parent: str, value: Any) -> str:
    local = effective_visibility(value)
    if parent == "hidden" or local == "hidden":
        return "hidden"
    if parent == "unknown":
        return "unknown"
    if parent == "dynamic" or local == "dynamic":
        return "dynamic"
    return "visible"


def object_kind(value: dict[str, Any]) -> str:
    if isinstance(value.get("particle"), str):
        return "particle"
    if isinstance(value.get("image"), str):
        return "image"
    if "text" in value or "font" in value:
        return "text"
    if "sound" in value:
        return "sound"
    if "light" in value:
        return "light"
    if "camera" in value or "path" in value:
        return "camera"
    if "shape" in value:
        return "shape"
    return "utility"


def _base_dir(path: str) -> str:
    parent = PurePosixPath(normalize_path(path)).parent
    return "" if parent == PurePosixPath(".") else parent.as_posix()


def _resource_identity(resource: ResolvedResource | None) -> dict[str, Any] | None:
    if resource is None:
        return None
    return {
        "origin": resource.origin,
        "relative_path": normalize_path(resource.relative_path),
        "sha256": resource.sha256(),
        "byte_count": resource.size,
    }


def _system_texture_identity(value: Any) -> tuple[str, str] | None:
    if not isinstance(value, dict):
        return None
    input_type = value.get("type")
    name = value.get("name")
    if not isinstance(input_type, str) or input_type.casefold() != "system":
        return None
    if not isinstance(name, str):
        return None
    normalized = normalize_path(name)
    if not normalized:
        return None
    role = {
        "$mediaThumbnail": "current",
        "$mediaPreviousThumbnail": "previous",
    }.get(normalized, "named")
    return normalized, role


def _system_texture_records(
    values: Any,
    *,
    sample_id: str,
    owner_occurrence: str,
    consumer_scope: str,
    provenance: str,
    effective_visibility: str,
) -> list[dict[str, Any]]:
    if not isinstance(values, list):
        return []
    records = []
    for slot_index, value in enumerate(values):
        identity = _system_texture_identity(value)
        if identity is None:
            continue
        system_name, system_role = identity
        location = {
            "sample_id": sample_id,
            "owner_occurrence": owner_occurrence,
            "slot_index": slot_index,
            "user_texture_provenance": provenance,
        }
        shape = {
            "consumer_scope": consumer_scope,
            "provider_kind": "system",
            "slot_state": "runtime-provided",
            "system_name": system_name,
            "system_role": system_role,
        }
        records.append({
            "occurrence_id": occurrence_id("system-texture", location),
            "family_key": family_key(
                "texture", f"{consumer_scope}-system-{system_role}", shape
            ),
            "revision_key": revision_key(shape, provenance),
            "domain": "texture",
            "kind": f"{consumer_scope}-system-{system_role}",
            "location": location,
            "effective_visibility": effective_visibility,
            "slot_index": slot_index,
            "slot_state": "runtime-provided",
            "state": f"system-{system_role}",
            "provenance": provenance,
            "provider_kind": "system",
            "consumer_scope": consumer_scope,
            "system_name": system_name,
            "system_role": system_role,
            "reference": system_name,
            "resource": None,
            "tex": None,
        })
    return records


def _texture_record(
    *,
    sample_id: str,
    owner_occurrence: str,
    owner_kind: str,
    slot_index: int,
    reference: str | None,
    provenance: str,
    view: SceneResourceView,
    effective_visibility: str,
) -> dict[str, Any]:
    location = {
        "sample_id": sample_id,
        "owner_occurrence": owner_occurrence,
        "slot_index": slot_index,
    }
    identity = occurrence_id("texture", location)
    if reference is None:
        shape = {
            "owner_kind": owner_kind,
            "provenance": provenance,
            "slot_state": "hole",
        }
        return {
            "occurrence_id": identity,
            "family_key": family_key("texture", owner_kind, shape),
            "revision_key": revision_key(shape),
            "domain": "texture",
            "kind": owner_kind,
            "location": location,
            "effective_visibility": effective_visibility,
            "slot_index": slot_index,
            "slot_state": "hole",
            "provenance": provenance,
            "reference": None,
            "resource": None,
            "tex": None,
        }

    normalized = normalize_path(reference)
    graph_source = _binding_source_kind(normalized) if owner_kind == "graph-binding" else None
    runtime_reference = owner_kind == "graph-binding" or normalized.casefold().startswith(
        ("_rt_", "_alias_", "$")
    )
    resource = None if runtime_reference else view.resolve_texture(normalized)
    state = "runtime-provided" if runtime_reference else ("resolved" if resource else "missing")
    tex = None
    if resource is not None and PurePosixPath(resource.relative_path).suffix.casefold() == ".tex":
        tex = parse_tex_summary(resource)
    shape = {
        "owner_kind": owner_kind,
        "provenance": provenance,
        "slot_state": state,
        "extension": PurePosixPath(resource.relative_path).suffix.casefold() if resource else None,
        "tex_format": tex.get("format_code") if isinstance(tex, dict) else None,
        "tex_volume": tex.get("is_volume") if isinstance(tex, dict) else None,
        "tex_animated": tex.get("is_animated") if isinstance(tex, dict) else None,
        "graph_source": graph_source,
    }
    resource_identity = _resource_identity(resource)
    return {
        "occurrence_id": identity,
        "family_key": family_key("texture", owner_kind, shape),
        "revision_key": revision_key(shape, normalized, resource_identity),
        "domain": "texture",
        "kind": owner_kind,
        "location": location,
        "effective_visibility": effective_visibility,
        "slot_index": slot_index,
        "slot_state": state,
        "provenance": provenance,
        "reference": normalized,
        "resource": resource_identity,
        "tex": tex,
    }


def _material_shape(pass_value: dict[str, Any]) -> dict[str, Any]:
    textures = pass_value.get("textures")
    return {
        "has_shader": isinstance(pass_value.get("shader"), str),
        "texture_slot_states": [
            "asset" if isinstance(value, str) and value.strip() else "hole"
            for value in textures
        ] if isinstance(textures, list) else [],
        "combo_keys": sorted(str(key) for key in (pass_value.get("combos") or {})),
        "constant_keys": sorted(
            str(key).casefold() for key in (pass_value.get("constantshadervalues") or {})
        ),
        "render_state": {
            key: pass_value.get(key)
            for key in ("blending", "depthtest", "depthwrite", "cullmode", "alphawriting")
        },
    }


def _definition_shape(definition: dict[str, Any]) -> dict[str, Any]:
    passes = [entry for entry in definition.get("passes") or [] if isinstance(entry, dict)]
    fbos = definition.get("fbos")
    return {
        "pass_count": len(passes),
        "pass_operations": [
            {
                "has_material": isinstance(entry.get("material"), str),
                "has_target": isinstance(entry.get("target"), str),
                "bind_count": len(entry.get("bind") or []) if isinstance(entry.get("bind"), list) else 0,
                "compose": entry.get("compose") is True,
            }
            for entry in passes
        ],
        "fbo_count": len(fbos) if isinstance(fbos, list) else (
            len(fbos) if isinstance(fbos, dict) else 0
        ),
        "dependency_count": len(definition.get("dependencies") or []),
    }


def census_image_layer(
    *,
    sample_id: str,
    object_index: int,
    layer: dict[str, Any],
    view: SceneResourceView,
    profiles: ParameterProfiles,
    layer_visibility: str,
) -> tuple[list[dict[str, Any]], list[dict[str, Any]], list[dict[str, Any]]]:
    image = layer.get("image")
    if not isinstance(image, str):
        return [], [], []
    location = {"sample_id": sample_id, "layer_id": layer.get("id"), "object_index": object_index}
    owner = occurrence_id("image-layer", location)
    model, model_resource, error = view.resolve_json(image)
    unclassified: list[dict[str, Any]] = []
    if not isinstance(model, dict):
        occurrence = {
            "occurrence_id": owner,
            "family_key": family_key("layer", "image", {"state": error or "malformed"}),
            "revision_key": revision_key(normalize_path(image), error),
            "domain": "layer",
            "kind": "image",
            "location": location,
            "effective_visibility": layer_visibility,
            "state": error or "malformed-model",
            "model": _resource_identity(model_resource),
            "parameter_profile_refs": [],
        }
        return [occurrence], [], unclassified

    known_model_keys = {
        "material", "autosize", "passthrough", "solidlayer", "cropoffset", "puppet",
        "fullscreen", "instanced", "nopadding", "projectlayer", "height", "width",
    }
    for key in sorted(set(model) - known_model_keys):
        unclassified.append({
            "domain": "image-model",
            "owner_occurrence": owner,
            "field": str(key),
            "value_shape": safe_value_shape(model[key]),
        })
    material_path = model.get("material")
    material = None
    material_resource = None
    material_error = "material-reference-missing"
    if isinstance(material_path, str):
        material, material_resource, material_error = view.resolve_json(
            material_path,
            _base_dir(image),
        )
    passes = [entry for entry in (material or {}).get("passes") or [] if isinstance(entry, dict)]
    layer_shape = {
        "model_keys": sorted(model),
        "material_passes": [_material_shape(entry) for entry in passes],
    }
    profile_refs: list[str] = []
    occurrence = {
        "occurrence_id": owner,
        "family_key": family_key("layer", "image", layer_shape),
        "revision_key": revision_key(
            _resource_identity(model_resource),
            _resource_identity(material_resource),
            layer_shape,
        ),
        "domain": "layer",
        "kind": "image",
        "location": location,
        "effective_visibility": layer_visibility,
        "state": "observed" if isinstance(material, dict) else material_error or "malformed-material",
        "model": _resource_identity(model_resource),
        "material": _resource_identity(material_resource),
        "model_flags": sorted(key for key in model if key != "material"),
        "material_pass_count": len(passes),
        "parameter_profile_refs": sorted(set(profile_refs)),
    }
    material_occurrences: list[dict[str, Any]] = []
    textures: list[dict[str, Any]] = []
    for pass_index, pass_value in enumerate(passes):
        pass_location = {**location, "material_pass_index": pass_index}
        pass_id = occurrence_id("image-material-pass", pass_location)
        constants = pass_value.get("constantshadervalues")
        refs = profile_parameter_mapping(
            profiles,
            "image-material-constant",
            constants,
            pass_id,
        )
        combos = pass_value.get("combos")
        refs += profile_parameter_mapping(profiles, "image-material-combo", combos, pass_id)
        pass_shape = _material_shape(pass_value)
        material_occurrences.append({
            "occurrence_id": pass_id,
            "family_key": family_key("material", "image-pass", pass_shape),
            "revision_key": revision_key(_resource_identity(material_resource), pass_index, pass_shape),
            "domain": "material",
            "kind": "image-pass",
            "location": pass_location,
            "effective_visibility": layer_visibility,
            "shader_identity": normalize_path(pass_value.get("shader", ""))
            if isinstance(pass_value.get("shader"), str) else None,
            "render_state": pass_shape["render_state"],
            "combo_keys": pass_shape["combo_keys"],
            "constant_keys": pass_shape["constant_keys"],
            "parameter_profile_refs": sorted(set(refs)),
        })
        slots = pass_value.get("textures")
        if isinstance(slots, list):
            for slot_index, reference in enumerate(slots):
                textures.append(_texture_record(
                    sample_id=sample_id,
                    owner_occurrence=pass_id,
                    owner_kind="image-material-slot",
                    slot_index=slot_index,
                    reference=reference if isinstance(reference, str) else None,
                    provenance="material",
                    view=view,
                    effective_visibility=layer_visibility,
                ))
        textures.extend(_system_texture_records(
            pass_value.get("usertextures"),
            sample_id=sample_id,
            owner_occurrence=pass_id,
            consumer_scope="base-image",
            provenance="material-user",
            effective_visibility=layer_visibility,
        ))
        instance = layer.get("instance")
        if pass_index == 0 and isinstance(instance, dict):
            textures.extend(_system_texture_records(
                instance.get("usertextures"),
                sample_id=sample_id,
                owner_occurrence=pass_id,
                consumer_scope="base-image",
                provenance="instance-user",
                effective_visibility=layer_visibility,
            ))
    return [occurrence, *material_occurrences], textures, unclassified


def census_effect(
    *,
    sample_id: str,
    object_index: int,
    layer: dict[str, Any],
    effect_index: int,
    effect: dict[str, Any],
    view: SceneResourceView,
    profiles: ParameterProfiles,
    layer_visibility: str,
) -> tuple[list[dict[str, Any]], list[dict[str, Any]], list[dict[str, Any]]]:
    path = effect.get("file")
    if not isinstance(path, str):
        return [], [], [{
            "domain": "effect-instance",
            "location": {
                "sample_id": sample_id,
                "layer_id": layer.get("id"),
                "object_index": object_index,
                "effect_index": effect_index,
            },
            "field": "file",
            "value_shape": safe_value_shape(path),
        }]
    location = {
        "sample_id": sample_id,
        "layer_id": layer.get("id"),
        "object_index": object_index,
        "effect_index": effect_index,
        "descriptor_id": effect.get("id"),
    }
    owner = occurrence_id("effect", location)
    visibility = nested_visibility(layer_visibility, effect.get("visible"))
    definition, definition_resource, error = view.resolve_json(path)
    if not isinstance(definition, dict):
        return [{
            "occurrence_id": owner,
            "family_key": family_key("effect", "unresolved", {"state": error or "malformed"}),
            "revision_key": revision_key(normalize_path(path), error),
            "domain": "effect",
            "kind": "unresolved",
            "location": location,
            "effective_visibility": visibility,
            "state": error or "malformed-definition",
            "definition_path": normalize_path(path),
            "definition": _resource_identity(definition_resource),
            "parameter_profile_refs": [],
        }], [], []

    definition_shape = _definition_shape(definition)
    effect_refs = []
    for pass_index, pass_value in enumerate(effect.get("passes") or []):
        if not isinstance(pass_value, dict):
            continue
        effect_refs += profile_parameter_mapping(
            profiles,
            "effect-constant",
            pass_value.get("constantshadervalues"),
            owner,
        )
        effect_refs += profile_parameter_mapping(
            profiles,
            "effect-combo",
            pass_value.get("combos"),
            owner,
        )
    occurrence = {
        "occurrence_id": owner,
        "family_key": family_key("effect", "authored-graph", definition_shape),
        "revision_key": revision_key(_resource_identity(definition_resource), definition_shape),
        "domain": "effect",
        "kind": "authored-graph",
        "location": location,
        "effective_visibility": visibility,
        "state": "observed",
        "definition_path": normalize_path(path),
        "definition": _resource_identity(definition_resource),
        "definition_shape": definition_shape,
        "instance_pass_count": len(effect.get("passes") or []),
        "parameter_profile_refs": sorted(set(effect_refs)),
    }
    occurrences = [occurrence]
    textures: list[dict[str, Any]] = []
    unclassified: list[dict[str, Any]] = []
    known_definition_keys = {
        "name", "group", "passes", "dependencies", "version", "replacementkey",
        "description", "preview", "gizmos", "editable", "performance", "fbos",
    }
    for key in sorted(set(definition) - known_definition_keys):
        unclassified.append({
            "domain": "effect-definition",
            "owner_occurrence": owner,
            "field": str(key),
            "value_shape": safe_value_shape(definition[key]),
        })

    definition_base = _base_dir(path)
    definition_passes = [entry for entry in definition.get("passes") or [] if isinstance(entry, dict)]
    instance_passes = [entry for entry in effect.get("passes") or [] if isinstance(entry, dict)]
    for definition_pass_index, definition_pass in enumerate(definition_passes):
        pass_location = {**location, "definition_pass_index": definition_pass_index}
        pass_id = occurrence_id("effect-definition-pass", pass_location)
        material_path = definition_pass.get("material")
        material = None
        material_resource = None
        material_error = None
        if isinstance(material_path, str):
            material, material_resource, material_error = view.resolve_json(
                material_path,
                definition_base,
            )
        material_passes = [entry for entry in (material or {}).get("passes") or [] if isinstance(entry, dict)]
        operation_shape = {
            "has_material": isinstance(material_path, str),
            "target": "named" if isinstance(definition_pass.get("target"), str) else "main",
            "binds": [
                {
                    "slot": entry.get("index"),
                    "source_kind": _binding_source_kind(entry.get("name")),
                }
                for entry in definition_pass.get("bind") or []
                if isinstance(entry, dict)
            ],
            "compose": definition_pass.get("compose") is True,
            "material_passes": [_material_shape(entry) for entry in material_passes],
        }
        occurrences.append({
            "occurrence_id": pass_id,
            "family_key": family_key("render-graph", "effect-pass", operation_shape),
            "revision_key": revision_key(
                _resource_identity(definition_resource),
                definition_pass_index,
                _resource_identity(material_resource),
                operation_shape,
            ),
            "domain": "render-graph",
            "kind": "effect-pass",
            "location": pass_location,
            "effective_visibility": occurrence["effective_visibility"],
            "state": "observed" if isinstance(material, dict) else material_error or "operation-only",
            "target_kind": operation_shape["target"],
            "target_identity": definition_pass.get("target"),
            "bindings": operation_shape["binds"],
            "compose": operation_shape["compose"],
            "material": _resource_identity(material_resource),
            "material_pass_count": len(material_passes),
            "parameter_profile_refs": [],
        })
        instance_pass = instance_passes[definition_pass_index] if definition_pass_index < len(instance_passes) else {}
        for material_pass_index, material_pass in enumerate(material_passes):
            material_location = {**pass_location, "material_pass_index": material_pass_index}
            material_id = occurrence_id("effect-material-pass", material_location)
            pass_shape = _material_shape(material_pass)
            refs = profile_parameter_mapping(
                profiles,
                "material-constant",
                material_pass.get("constantshadervalues"),
                material_id,
            )
            refs += profile_parameter_mapping(
                profiles,
                "material-combo",
                material_pass.get("combos"),
                material_id,
            )
            occurrences.append({
                "occurrence_id": material_id,
                "family_key": family_key("material", "effect-pass", pass_shape),
                "revision_key": revision_key(
                    _resource_identity(material_resource), material_pass_index, pass_shape
                ),
                "domain": "material",
                "kind": "effect-pass",
                "location": material_location,
                "effective_visibility": occurrence["effective_visibility"],
                "shader_identity": normalize_path(material_pass.get("shader", ""))
                if isinstance(material_pass.get("shader"), str) else None,
                "render_state": pass_shape["render_state"],
                "combo_keys": pass_shape["combo_keys"],
                "constant_keys": pass_shape["constant_keys"],
                "parameter_profile_refs": sorted(set(refs)),
            })
            material_slots = material_pass.get("textures")
            instance_slots = instance_pass.get("textures") if material_pass_index == 0 else None
            slot_count = max(
                len(material_slots) if isinstance(material_slots, list) else 0,
                len(instance_slots) if isinstance(instance_slots, list) else 0,
            )
            for slot_index in range(slot_count):
                material_reference = (
                    material_slots[slot_index]
                    if isinstance(material_slots, list) and slot_index < len(material_slots)
                    else None
                )
                instance_reference = (
                    instance_slots[slot_index]
                    if isinstance(instance_slots, list) and slot_index < len(instance_slots)
                    else None
                )
                reference = instance_reference if isinstance(instance_reference, str) else material_reference
                provenance = "instance" if isinstance(instance_reference, str) else "material"
                textures.append(_texture_record(
                    sample_id=sample_id,
                    owner_occurrence=material_id,
                    owner_kind="effect-material-slot",
                    slot_index=slot_index,
                    reference=reference if isinstance(reference, str) else None,
                    provenance=provenance,
                    view=view,
                    effective_visibility=visibility,
                ))
            textures.extend(_system_texture_records(
                material_pass.get("usertextures"),
                sample_id=sample_id,
                owner_occurrence=material_id,
                consumer_scope="effect",
                provenance="material-user",
                effective_visibility=visibility,
            ))
            if material_pass_index == 0:
                textures.extend(_system_texture_records(
                    instance_pass.get("usertextures"),
                    sample_id=sample_id,
                    owner_occurrence=material_id,
                    consumer_scope="effect",
                    provenance="instance-user",
                    effective_visibility=visibility,
                ))
        for binding_index, binding in enumerate(definition_pass.get("bind") or []):
            if not isinstance(binding, dict) or not isinstance(binding.get("index"), int):
                continue
            textures.append(_texture_record(
                sample_id=sample_id,
                owner_occurrence=pass_id,
                owner_kind="graph-binding",
                slot_index=binding["index"],
                reference=binding.get("name") if isinstance(binding.get("name"), str) else None,
                provenance="explicit-binding",
                view=view,
                effective_visibility=visibility,
            ))
    raw_fbos = definition.get("fbos") or []
    fbo_values = (
        list(raw_fbos.values())
        if isinstance(raw_fbos, dict)
        else raw_fbos
    )
    for fbo_index, fbo in enumerate(fbo_values):
        if not isinstance(fbo, dict):
            unclassified.append({
                "domain": "render-target",
                "owner_occurrence": owner,
                "field": f"fbos[{fbo_index}]",
                "value_shape": safe_value_shape(fbo),
            })
            continue
        fbo_location = {**location, "fbo_index": fbo_index}
        fbo_id = occurrence_id("render-target", fbo_location)
        shape = {
            "keys": sorted(fbo),
            "format": fbo.get("format"),
            "uvs": fbo.get("uvs"),
            "scale": safe_value_shape(fbo.get("scale")),
            "width": safe_value_shape(fbo.get("width")),
            "height": safe_value_shape(fbo.get("height")),
            "unique": fbo.get("unique"),
        }
        refs = [profiles.add("render-target", key, value, fbo_id) for key, value in sorted(fbo.items())]
        occurrences.append({
            "occurrence_id": fbo_id,
            "family_key": family_key("render-target", "fbo", shape),
            "revision_key": revision_key(_resource_identity(definition_resource), fbo_index, shape),
            "domain": "render-target",
            "kind": "fbo",
            "location": fbo_location,
            "effective_visibility": occurrence["effective_visibility"],
            "target_identity": fbo.get("name"),
            "format": fbo.get("format"),
            "uvs": fbo.get("uvs"),
            "parameter_profile_refs": refs,
        })
    return occurrences, textures, unclassified


def _binding_source_kind(value: Any) -> str:
    if not isinstance(value, str):
        return "invalid"
    normalized = normalize_path(value).casefold()
    if normalized in {"previous", "current"}:
        return normalized
    if normalized.startswith("_rt_"):
        return "render-target"
    if normalized.startswith("_alias_"):
        return "alias"
    return "named-target"


def summarize_texture_families(textures: list[dict[str, Any]]) -> dict[str, Any]:
    states = Counter(str(item.get("slot_state", "unknown")) for item in textures)
    formats = Counter(
        str(item["tex"]["format_code"])
        for item in textures
        if isinstance(item.get("tex"), dict) and item["tex"].get("state") == "parsed"
    )
    return {
        "occurrence_count": len(textures),
        "state_counts": dict(sorted(states.items())),
        "tex_format_counts": dict(sorted(formats.items())),
    }
