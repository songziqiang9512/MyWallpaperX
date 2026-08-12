#!/usr/bin/env python3
"""Payload-free inventory of every resource physically present in a Scene PKG."""

from __future__ import annotations

import json
import re
from pathlib import PurePosixPath
from typing import Any, Callable

from scene_capability_census_io import (
    PkgArchive,
    ResolvedResource,
    SceneResourceView,
    decode_json,
    normalize_path,
    package_category,
    parse_tex_summary,
)
from scene_capability_census_profiles import (
    family_key,
    occurrence_id,
    revision_key,
    safe_value_shape,
)


UNIFORM_PATTERN = re.compile(
    r"\buniform\s+(?:(?:lowp|mediump|highp)\s+)?"
    r"([A-Za-z_][A-Za-z0-9_]*)\s+([A-Za-z_][A-Za-z0-9_]*)"
)
INCLUDE_PATTERN = re.compile(r"^\s*#\s*include\b", re.MULTILINE)
ANNOTATION_PATTERN = re.compile(r"//\s*(?:\[[^\]]+\]\s*)?(\{[^\r\n]+\})")
SAMPLER_ANNOTATION_PATTERN = re.compile(
    r"\buniform\s+(?:lowp\s+|mediump\s+|highp\s+)?sampler\w*\s+"
    r"([A-Za-z_][A-Za-z0-9_]*)\s*;\s*//\s*(?:\[([^\]]+)\]\s*)?(\{[^\r\n]+\})"
)
UNIFORM_ANNOTATION_PATTERN = re.compile(
    r"\buniform\s+(?:lowp\s+|mediump\s+|highp\s+)?"
    r"([A-Za-z_][A-Za-z0-9_]*)\s+([A-Za-z_][A-Za-z0-9_]*)\s*;\s*"
    r"//\s*(?:\[([^\]]+)\]\s*)?(\{[^\r\n]+\})"
)


def _decode_source(payload: bytes) -> str | None:
    for encoding in ("utf-8-sig", "latin-1"):
        try:
            return payload.decode(encoding)
        except UnicodeDecodeError:
            continue
    return None


def _shader_profile(resource: ResolvedResource) -> dict[str, Any]:
    source = _decode_source(resource.read_bytes())
    if source is None:
        return {"state": "malformed-text"}
    uniforms = sorted({
        (value_type, name)
        for value_type, name in UNIFORM_PATTERN.findall(source)
    })
    annotation_fields: set[str] = set()
    combo_names: set[str] = set()
    format_combo_names: set[str] = set()
    sampler_modes: set[str] = set()
    sampler_annotations: list[dict[str, Any]] = []
    uniform_annotations: list[dict[str, Any]] = []
    for raw_object in ANNOTATION_PATTERN.findall(source):
        try:
            value = json.loads(raw_object)
        except json.JSONDecodeError:
            continue
        if not isinstance(value, dict):
            continue
        annotation_fields.update(str(key) for key in value)
        combo = value.get("combo")
        if isinstance(combo, str):
            combo_names.add(combo)
        format_combo = value.get("formatcombo")
        if isinstance(format_combo, str):
            format_combo_names.add(format_combo)
        mode = value.get("mode")
        if isinstance(mode, str):
            sampler_modes.add(mode.casefold())
    for name, marker, raw_object in SAMPLER_ANNOTATION_PATTERN.findall(source):
        try:
            value = json.loads(raw_object)
        except json.JSONDecodeError:
            continue
        if not isinstance(value, dict):
            continue
        slot_match = re.fullmatch(r"g_Texture(\d+)", name, re.IGNORECASE)
        sampler_annotations.append({
            "name": name,
            "slot": int(slot_match.group(1)) if slot_match else None,
            "marker": marker.casefold() if marker else None,
            "fields": sorted(str(key) for key in value),
            "mode": value.get("mode").casefold() if isinstance(value.get("mode"), str) else None,
            "combo": value.get("combo") if isinstance(value.get("combo"), str) else None,
            "formatcombo": value.get("formatcombo")
            if isinstance(value.get("formatcombo"), str) else None,
            "default": normalize_path(value["default"])
            if not marker and isinstance(value.get("default"), str) else None,
        })
    for value_type, name, marker, raw_object in UNIFORM_ANNOTATION_PATTERN.findall(source):
        try:
            value = json.loads(raw_object)
        except json.JSONDecodeError:
            continue
        if not isinstance(value, dict):
            continue
        uniform_annotations.append({
            "type": value_type,
            "name": name,
            "marker": marker.casefold() if marker else None,
            "fields": {
                str(key): safe_value_shape(child)
                for key, child in sorted(value.items(), key=lambda item: str(item[0]).casefold())
            },
        })
    return {
        "state": "observed-source",
        "byte_count": resource.size,
        "line_count": source.count("\n") + 1,
        "include_count": len(INCLUDE_PATTERN.findall(source)),
        "uniform_count": len(uniforms),
        "uniforms": [
            {"type": value_type, "name": name}
            for value_type, name in uniforms
        ],
        "annotation_fields": sorted(annotation_fields),
        "combo_names": sorted(combo_names),
        "format_combo_names": sorted(format_combo_names),
        "sampler_modes": sorted(sampler_modes),
        "sampler_annotations": sorted(
            sampler_annotations,
            key=lambda value: (value["slot"] is None, value["slot"] or -1, value["name"]),
        ),
        "uniform_annotations": sorted(
            uniform_annotations,
            key=lambda value: (value["name"].casefold(), value["type"], value["marker"] or ""),
        ),
    }


def census_package_resources(
    *,
    sample_id: str,
    archive: PkgArchive,
    observe_json: Callable[[ResolvedResource, Any], None],
    view: SceneResourceView,
) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    occurrences: list[dict[str, Any]] = []
    diagnostics: list[dict[str, Any]] = []
    for entry in archive.entries:
        resource = ResolvedResource(
            origin="package",
            relative_path=entry.path,
            archive=archive,
            entry=entry,
        )
        extension = PurePosixPath(entry.path).suffix.casefold()
        category = package_category(entry.path)
        location = {
            "sample_id": sample_id,
            "package_entry_index": entry.index,
        }
        identity = occurrence_id("package-resource", location)
        common = {
            "occurrence_id": identity,
            "location": location,
            "effective_visibility": "not-applicable",
            "resource": {
                "origin": "package",
                "relative_path": normalize_path(entry.path),
                "sha256": resource.sha256(),
                "byte_count": entry.size,
            },
        }

        if extension == ".tex":
            tex = parse_tex_summary(resource)
            shape = {
                "extension": extension,
                "container": tex.get("effective_container_version"),
                "format": tex.get("format_code"),
                "compression": tex.get("compression_codes"),
                "is_volume": tex.get("is_volume"),
                "is_animated": tex.get("is_animated"),
                "is_video_mp4": tex.get("is_video_mp4"),
                "state": tex.get("state"),
            }
            occurrences.append({
                **common,
                "family_key": family_key("texture", "package-resource", shape),
                "revision_key": revision_key(common["resource"]),
                "domain": "texture",
                "kind": "package-resource",
                "slot_state": "stored" if tex.get("state") == "parsed" else "malformed",
                "provenance": "package",
                "reference": normalize_path(entry.path),
                "tex": tex,
            })
            continue

        if extension in {".frag", ".vert", ".comp", ".inc"}:
            profile = _shader_profile(resource)
            shape = {
                "extension": extension,
                "state": profile["state"],
                "uniforms": [
                    (uniform["type"], uniform["name"])
                    for uniform in profile.get("uniforms", [])
                ],
                "annotation_fields": profile.get("annotation_fields", []),
                "combo_names": profile.get("combo_names", []),
                "format_combo_names": profile.get("format_combo_names", []),
                "sampler_modes": profile.get("sampler_modes", []),
                "sampler_annotations": [
                    {
                        "slot": item["slot"],
                        "marker": item["marker"],
                        "fields": item["fields"],
                        "mode": item["mode"],
                        "combo": item["combo"],
                        "formatcombo": item["formatcombo"],
                        "has_default": item["default"] is not None,
                    }
                    for item in profile.get("sampler_annotations", [])
                ],
                "uniform_annotations": profile.get("uniform_annotations", []),
            }
            occurrences.append({
                **common,
                "family_key": family_key("shader", extension.lstrip("."), shape),
                "revision_key": revision_key(common["resource"]),
                "domain": "shader",
                "kind": extension.lstrip("."),
                "shader_features": {
                    "uniform_count": profile.get("uniform_count", 0),
                    "annotation_fields": profile.get("annotation_fields", []),
                    "combo_names": profile.get("combo_names", []),
                    "format_combo_names": profile.get("format_combo_names", []),
                    "sampler_modes": profile.get("sampler_modes", []),
                    "uniform_annotations": profile.get("uniform_annotations", []),
                },
                "profile": profile,
            })
            for sampler in profile.get("sampler_annotations", []):
                default = sampler.get("default")
                if not isinstance(default, str):
                    continue
                resolved = view.resolve_texture(default)
                tex = (
                    parse_tex_summary(resolved)
                    if resolved is not None
                    and PurePosixPath(resolved.relative_path).suffix.casefold() == ".tex"
                    else None
                )
                texture_shape = {
                    "state": "resolved" if resolved else "missing",
                    "mode": sampler.get("mode"),
                    "combo": sampler.get("combo") is not None,
                    "formatcombo": sampler.get("formatcombo") is not None,
                    "tex_format": tex.get("format_code") if isinstance(tex, dict) else None,
                }
                default_location = {
                    "sample_id": sample_id,
                    "owner_occurrence": identity,
                    "sampler_name": sampler["name"],
                    "slot_index": sampler.get("slot"),
                }
                resource_identity = ({
                    "origin": resolved.origin,
                    "relative_path": normalize_path(resolved.relative_path),
                    "sha256": resolved.sha256(),
                    "byte_count": resolved.size,
                } if resolved else None)
                occurrences.append({
                    "occurrence_id": occurrence_id("shader-default-texture", default_location),
                    "family_key": family_key(
                        "texture", "shader-default-slot", texture_shape
                    ),
                    "revision_key": revision_key(texture_shape, default, resource_identity),
                    "domain": "texture",
                    "kind": "shader-default-slot",
                    "location": default_location,
                    "effective_visibility": "unknown",
                    "slot_index": sampler.get("slot"),
                    "slot_state": texture_shape["state"],
                    "provenance": "shader-default",
                    "reference": default,
                    "resource": resource_identity,
                    "tex": tex,
                })
            continue

        json_state = None
        if extension in {".json", ".tex-json"}:
            try:
                value = decode_json(resource.read_bytes())
            except ValueError as error:
                json_state = str(error)
                diagnostics.append({
                    "code": "package-json-malformed",
                    "entry_index": entry.index,
                    "category": category,
                })
            else:
                observe_json(resource, value)
                json_state = "parsed"
        shape = {
            "category": category,
            "extension": extension or "<none>",
            "json_state": json_state,
        }
        occurrences.append({
            **common,
            "family_key": family_key("resource", category, shape),
            "revision_key": revision_key(common["resource"]),
            "domain": "resource",
            "kind": category,
            "extension": extension or None,
            "json_state": json_state,
        })
    return occurrences, diagnostics
