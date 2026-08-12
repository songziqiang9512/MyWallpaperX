#!/usr/bin/env python3
"""Recursive particle-definition census for authored Scene samples."""

from __future__ import annotations

from collections import Counter, deque
from pathlib import PurePosixPath
from typing import Any

from scene_capability_census_io import SceneResourceView, normalize_path, parse_tex_summary
from scene_capability_census_profiles import (
    ParameterProfiles,
    family_key,
    occurrence_id,
    revision_key,
    safe_value_shape,
)
from scene_capability_census_effects import effective_visibility


PARTICLE_COMPONENT_CATEGORIES = (
    "emitter",
    "initializer",
    "operator",
    "renderer",
    "controlpoint",
    "children",
)


def census_particle_layer(
    *,
    sample_id: str,
    object_index: int,
    layer: dict[str, Any],
    view: SceneResourceView,
    profiles: ParameterProfiles,
    layer_visibility: str,
) -> tuple[list[dict[str, Any]], list[dict[str, Any]], list[dict[str, Any]]]:
    particle_path = layer.get("particle")
    if not isinstance(particle_path, str):
        return [], [], []
    root_location = {
        "sample_id": sample_id,
        "layer_id": layer.get("id"),
        "object_index": object_index,
    }
    root_id = occurrence_id("particle-layer", root_location)
    layer_refs = []
    override = layer.get("instanceoverride")
    if isinstance(override, dict):
        for key, value in sorted(override.items()):
            if key == "id":
                continue
            layer_refs.append(profiles.add("particle-instance-override", key, value, root_id))

    root_shape = {
        "has_instance_override": isinstance(override, dict),
        "override_keys": sorted(str(key) for key in override if key != "id")
        if isinstance(override, dict) else [],
    }
    occurrences: list[dict[str, Any]] = [{
        "occurrence_id": root_id,
        "family_key": family_key("particle", "layer", root_shape),
        "revision_key": revision_key(normalize_path(particle_path), root_shape),
        "domain": "particle",
        "kind": "layer",
        "location": root_location,
        "effective_visibility": layer_visibility,
        "definition_path": normalize_path(particle_path),
        "parameter_profile_refs": sorted(set(layer_refs)),
    }]
    textures: list[dict[str, Any]] = []
    unclassified: list[dict[str, Any]] = []

    pending = deque([(normalize_path(particle_path), None, 0, frozenset())])
    visited: set[str] = set()
    maximum_depth = 0
    while pending:
        path, parent_definition, depth, ancestors = pending.popleft()
        identity = path.casefold()
        maximum_depth = max(maximum_depth, depth)
        if identity in ancestors:
            unclassified.append({
                "domain": "particle-child",
                "owner_occurrence": root_id,
                "field": "cycle",
                "value_shape": {"kind": "cycle", "depth": depth},
            })
            continue
        if identity in visited:
            continue
        visited.add(identity)
        value, resource, error = view.resolve_json(path)
        definition_location = {
            **root_location,
            "definition_path": path,
            "definition_depth": depth,
        }
        definition_id = occurrence_id("particle-definition", definition_location)
        if not isinstance(value, dict):
            occurrences.append({
                "occurrence_id": definition_id,
                "family_key": family_key("particle", "unresolved-definition", {"state": error}),
                "domain": "particle",
                "kind": "definition",
                "location": definition_location,
                "effective_visibility": layer_visibility,
                "revision_key": revision_key(normalize_path(path), error),
                "state": error or "malformed",
                "parent_definition": parent_definition,
                "parameter_profile_refs": [],
            })
            continue

        component_counts = {
            category: len(value.get(category) or []) if isinstance(value.get(category), list) else 0
            for category in PARTICLE_COMPONENT_CATEGORIES
        }
        definition_shape = {
            "keys": sorted(value),
            "component_counts": component_counts,
            "component_names": {
                category: [
                    (
                        "child-definition"
                        if category == "children"
                        else str(
                            component.get("name")
                            or component.get("type")
                            or component.get("id")
                        ).casefold()
                    )
                    for component in value.get(category) or []
                    if isinstance(component, dict)
                ]
                for category in PARTICLE_COMPONENT_CATEGORIES
            },
            "has_material": isinstance(value.get("material"), str),
        }
        definition_refs = []
        for key in (
            "maxcount", "starttime", "flags", "animationmode", "sequencemultiplier"
        ):
            if key in value:
                definition_refs.append(profiles.add("particle-general", key, value[key], definition_id))
        occurrences.append({
            "occurrence_id": definition_id,
            "family_key": family_key("particle", "definition", definition_shape),
            "revision_key": revision_key(
                {
                    "origin": resource.origin if resource else None,
                    "path": resource.relative_path if resource else path,
                    "sha256": resource.sha256() if resource else None,
                },
                definition_shape,
            ),
            "domain": "particle",
            "kind": "definition",
            "location": definition_location,
            "effective_visibility": layer_visibility,
            "state": "observed",
            "parent_definition": parent_definition,
            "component_counts": component_counts,
            "parameter_profile_refs": sorted(set(definition_refs)),
        })

        known_keys = {
            "emitter", "initializer", "material", "maxcount", "operator", "starttime",
            "renderer", "controlpoint", "children", "flags", "animationmode",
            "sequencemultiplier",
        }
        for key in sorted(set(value) - known_keys):
            unclassified.append({
                "domain": "particle-definition",
                "owner_occurrence": definition_id,
                "field": str(key),
                "value_shape": safe_value_shape(value[key]),
            })

        for category in PARTICLE_COMPONENT_CATEGORIES:
            for component_index, component in enumerate(value.get(category) or []):
                if not isinstance(component, dict):
                    unclassified.append({
                        "domain": f"particle-{category}",
                        "owner_occurrence": definition_id,
                        "field": f"{category}[{component_index}]",
                        "value_shape": safe_value_shape(component),
                    })
                    continue
                component_location = {
                    **definition_location,
                    "component_category": category,
                    "component_index": component_index,
                }
                component_id = occurrence_id("particle-component", component_location)
                component_name = str(
                    component.get("name") or component.get("type") or component.get("id") or "unknown"
                ).casefold()
                family_component_name = (
                    "child-definition" if category == "children" else component_name
                )
                parameter_keys = sorted(
                    str(key) for key in component if key not in {"id", "name", "type"}
                )
                component_shape = {
                    "category": category,
                    "name": family_component_name,
                    "parameter_keys": parameter_keys,
                    "parameter_shapes": {
                        key: safe_value_shape(component[key])
                        for key in parameter_keys
                    },
                }
                refs = [
                    profiles.add(
                        f"particle-{category}-{family_component_name}",
                        key,
                        component[key],
                        component_id,
                    )
                    for key in parameter_keys
                ]
                occurrences.append({
                    "occurrence_id": component_id,
                    "family_key": family_key(
                        "particle",
                        f"{category}-{family_component_name}",
                        component_shape,
                    ),
                    "revision_key": revision_key(component_index, component_shape),
                    "domain": "particle",
                    "kind": category,
                    "component_name": component_name,
                    "location": component_location,
                    "effective_visibility": layer_visibility,
                    "parameter_keys": parameter_keys,
                    "parameter_profile_refs": sorted(set(refs)),
                })
                if category == "children":
                    child_path = component.get("name")
                    if isinstance(child_path, str) and child_path.strip():
                        pending.append((
                            normalize_path(child_path),
                            path,
                            depth + 1,
                            ancestors | {identity},
                        ))

        material_path = value.get("material")
        if isinstance(material_path, str):
            material, material_resource, material_error = view.resolve_json(material_path)
            material_location = {**definition_location, "particle_material": material_path}
            material_id = occurrence_id("particle-material", material_location)
            passes = [entry for entry in (material or {}).get("passes") or [] if isinstance(entry, dict)]
            material_shape = {
                "pass_count": len(passes),
                "passes": [
                    {
                        "has_shader": isinstance(entry.get("shader"), str),
                        "texture_slot_count": len(entry.get("textures") or [])
                        if isinstance(entry.get("textures"), list) else 0,
                        "render_state": {
                            key: entry.get(key)
                            for key in (
                                "blending", "depthtest", "depthwrite", "cullmode", "alphawriting"
                            )
                        },
                    }
                    for entry in passes
                ],
            }
            occurrences.append({
                "occurrence_id": material_id,
                "family_key": family_key("particle", "material", material_shape),
                "revision_key": revision_key(
                    material_resource.sha256() if material_resource else None,
                    material_shape,
                ),
                "domain": "particle",
                "kind": "material",
                "location": material_location,
                "effective_visibility": layer_visibility,
                "state": "observed" if isinstance(material, dict) else material_error or "malformed",
                "parameter_profile_refs": [],
            })
            for pass_index, pass_value in enumerate(passes):
                slots = pass_value.get("textures")
                if not isinstance(slots, list):
                    continue
                for slot_index, reference in enumerate(slots):
                    texture_location = {
                        "sample_id": sample_id,
                        "owner_occurrence": material_id,
                        "pass_index": pass_index,
                        "slot_index": slot_index,
                    }
                    texture_id = occurrence_id("particle-texture", texture_location)
                    resolved = view.resolve_texture(reference) if isinstance(reference, str) else None
                    state = "resolved" if resolved else ("hole" if reference is None else "missing")
                    texture_shape = {
                        "state": state,
                        "extension": (
                            resolved.relative_path.rsplit(".", 1)[-1].casefold()
                            if resolved and "." in resolved.relative_path else None
                        ),
                    }
                    tex = (
                        parse_tex_summary(resolved)
                        if resolved
                        and PurePosixPath(resolved.relative_path).suffix.casefold() == ".tex"
                        else None
                    )
                    if isinstance(tex, dict):
                        texture_shape.update({
                            "tex_format": tex.get("format_code"),
                            "tex_volume": tex.get("is_volume"),
                            "tex_animated": tex.get("is_animated"),
                        })
                    textures.append({
                        "occurrence_id": texture_id,
                        "family_key": family_key("texture", "particle-material-slot", texture_shape),
                        "revision_key": revision_key(
                            texture_shape,
                            normalize_path(reference) if isinstance(reference, str) else None,
                            resolved.sha256() if resolved else None,
                        ),
                        "domain": "texture",
                        "kind": "particle-material-slot",
                        "location": texture_location,
                        "effective_visibility": layer_visibility,
                        "slot_index": slot_index,
                        "slot_state": state,
                        "provenance": "particle-material",
                        "reference": normalize_path(reference) if isinstance(reference, str) else None,
                        "resource": ({
                            "origin": resolved.origin,
                            "relative_path": resolved.relative_path,
                            "sha256": resolved.sha256(),
                            "byte_count": resolved.size,
                        } if resolved else None),
                        "tex": tex,
                    })

    occurrences[0]["reachable_definition_count"] = len(visited)
    occurrences[0]["maximum_child_depth"] = maximum_depth
    return occurrences, textures, unclassified


def particle_summary(occurrences: list[dict[str, Any]]) -> dict[str, Any]:
    components = Counter(
        f"{item['kind']}:{(
            'child-definition'
            if item['kind'] == 'children'
            else item.get('component_name', '')
        )}".rstrip(":")
        for item in occurrences
        if item.get("domain") == "particle"
    )
    return {
        "occurrence_count": len(occurrences),
        "component_counts": dict(sorted(components.items())),
    }
