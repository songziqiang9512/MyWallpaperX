#!/usr/bin/env python3
"""Build the deterministic, read-only authored capability census for all Scene samples.

This inventory answers what the corpus declares, not what the current renderer
executes. It never retains shader, SceneScript, layer text, image, or binary payloads.
Runtime support and visual equivalence remain separate evidence.
"""

from __future__ import annotations

import argparse
import json
import sys
from collections import Counter, defaultdict
from pathlib import Path, PurePosixPath
from typing import Any, Iterable

from scene_capability_census_effects import (
    census_effect,
    census_image_layer,
    effective_visibility,
    object_kind,
    summarize_texture_families,
)
from scene_capability_census_io import (
    PkgArchive,
    ResolvedResource,
    SceneResourceView,
    atomic_write,
    canonical_sha256,
    decode_json,
    directory_manifest,
    ensure_outputs_outside_roots,
    iter_numeric_sample_directories,
    normalize_path,
    package_category,
    parse_tex_summary,
    path_identity,
    sha256_bytes,
    sha256_file,
    tree_manifest,
)
from scene_capability_census_particles import census_particle_layer, particle_summary
from scene_capability_census_resources import census_package_resources
from scene_capability_census_profiles import (
    ParameterProfiles,
    SchemaInventory,
    family_key,
    merge_counts,
    occurrence_id,
    recursive_dynamic_features,
    revision_key,
    safe_value_shape,
)


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SAMPLES_ROOT = Path.home() / "Movies/MyWallpaperX/创意工坊/Scene"
DEFAULT_STOCK_ROOT = (
    REPOSITORY_ROOT / "MyWallpaperX/Resources/SceneStockAssets.bundle/assets"
)
DEFAULT_MATRIX = REPOSITORY_ROOT / "script/scene_wallpaper_full_sample_matrix.json"
DEFAULT_LEDGER = REPOSITORY_ROOT / "script/scene_capability_repair_ledger.json"

DOMAINS = (
    "resource",
    "shader",
    "layer",
    "material",
    "effect",
    "render-graph",
    "render-target",
    "texture",
    "particle",
    "dynamic-input",
    "project-property",
)

REPAIR_STATUS_CONTRACT = {
    "repair_state": [
        "untriaged", "diagnosed", "in-progress", "implemented", "bounded-verified",
    ],
    "runtime_proof_state": [
        "none", "partial-chain", "visible-chain-closed", "official-golden-equivalent",
    ],
    "regression_protection_state": [
        "none", "synthetic", "targeted-runtime", "milestone",
    ],
}

GENERATOR_PATHS = (
    "script/scene_capability_census.py",
    "script/scene_capability_census_effects.py",
    "script/scene_capability_census_io.py",
    "script/scene_capability_census_particles.py",
    "script/scene_capability_census_profiles.py",
    "script/scene_capability_census_resources.py",
)


def generator_manifest() -> dict[str, Any]:
    files = {
        relative: sha256_file(REPOSITORY_ROOT / relative)
        for relative in GENERATOR_PATHS
    }
    return {
        "files": files,
        "sha256": canonical_sha256(files),
    }


def json_document_kind(relative_path: str, scene_entry: str) -> str:
    normalized = normalize_path(relative_path).casefold()
    if normalized.endswith(".tex-json"):
        return "texture-sidecar"
    if normalized == normalize_path(scene_entry).casefold():
        return "scene"
    components = normalized.split("/")
    if "materials" in components or components[0] == "materials":
        return "material-definition"
    if components[0] == "effects":
        return "effect-definition"
    if components[0] == "particles":
        return "particle-definition"
    if components[0] == "models":
        return "model-definition"
    return "package-json"


def project_package_name(project: dict[str, Any]) -> tuple[str, str]:
    raw_entry = project.get("file")
    entry = normalize_path(raw_entry) if isinstance(raw_entry, str) and raw_entry.strip() else "scene.json"
    entry_name = PurePosixPath(entry).name
    package_name = str(PurePosixPath(entry_name).with_suffix(".pkg"))
    return entry_name, package_name


def matrix_identity(path: Path) -> dict[str, Any]:
    if not path.is_file():
        return {"state": "missing", "relative_path": relative_repo_path(path)}
    payload = json.loads(path.read_text(encoding="utf-8"))
    samples = payload.get("samples") if isinstance(payload, dict) else None
    ids = [str(item.get("id")) for item in samples or [] if isinstance(item, dict)]
    return {
        "state": "loaded",
        "relative_path": relative_repo_path(path),
        "sha256": sha256_file(path),
        "sample_count": len(ids),
        "sample_ids": sorted(ids),
    }


def relative_repo_path(path: Path) -> str:
    try:
        return path.resolve().relative_to(REPOSITORY_ROOT.resolve()).as_posix()
    except ValueError:
        return path.name


def corpus_manifest(samples: list[Path]) -> str:
    return sha256_bytes(("\n".join(sample.name for sample in samples) + "\n").encode("utf-8"))


def project_title_metadata(value: Any, sample_id: str) -> str:
    if not isinstance(value, str):
        return sample_id
    return " ".join(value.replace("\x00", " ").split())[:256] or sample_id


def _object_parameters(
    profiles: ParameterProfiles,
    sample_id: str,
    object_index: int,
    value: dict[str, Any],
    owner: str,
) -> list[str]:
    ignored = {
        "id", "name", "image", "particle", "effects", "instanceoverride", "text",
        "font", "sound", "light", "dependencies", "parent", "animationlayers",
    }
    return [
        profiles.add(f"{object_kind(value)}-object", key, item, owner)
        for key, item in sorted(value.items())
        if key not in ignored
    ]


def authored_layer_visibilities(objects: list[Any]) -> list[str]:
    by_id = {
        value.get("id"): index
        for index, value in enumerate(objects)
        if isinstance(value, dict) and isinstance(value.get("id"), int)
    }
    cache: dict[int, str] = {}

    def resolve(index: int, ancestors: frozenset[int]) -> str:
        if index in cache:
            return cache[index]
        if index in ancestors:
            return "unknown"
        value = objects[index]
        if not isinstance(value, dict):
            return "unknown"
        local = effective_visibility(value.get("visible"))
        parent_index = by_id.get(value.get("parent"))
        if parent_index is None:
            result = local
        else:
            parent = resolve(parent_index, ancestors | {index})
            if parent == "hidden" or local == "hidden":
                result = "hidden"
            elif parent == "unknown":
                result = "unknown"
            elif parent == "dynamic" or local == "dynamic":
                result = "dynamic"
            else:
                result = "visible"
        cache[index] = result
        return result

    return [resolve(index, frozenset()) for index in range(len(objects))]


def _dynamic_occurrences(
    *,
    sample_id: str,
    root: dict[str, Any],
    objects: list[Any],
) -> list[dict[str, Any]]:
    results: list[dict[str, Any]] = []

    def visit(
        value: Any,
        path_pattern: list[str],
        json_pointer: list[str],
        layer_id: Any = None,
    ) -> None:
        if isinstance(value, dict):
            source_kinds = []
            if isinstance(value.get("script"), str):
                source_kinds.append("scenescript")
            if isinstance(value.get("user"), str):
                source_kinds.append("user-property")
            if "animation" in value or "timeline" in value:
                source_kinds.append("timeline")
            if "condition" in value:
                source_kinds.append("condition")
            if source_kinds:
                location = {
                    "sample_id": sample_id,
                    "layer_id": layer_id,
                    "path_pattern": ".".join(path_pattern),
                    "json_pointer": "/" + "/".join(json_pointer),
                }
                shape = {
                    "sources": sorted(source_kinds),
                    "keys": sorted(value),
                    "value": safe_value_shape(value),
                }
                results.append({
                    "occurrence_id": occurrence_id("dynamic-input", location),
                    "family_key": family_key("dynamic-input", "+".join(sorted(source_kinds)), shape),
                    "revision_key": canonical_sha256(value),
                    "domain": "dynamic-input",
                    "kind": "+".join(sorted(source_kinds)),
                    "location": location,
                    "effective_visibility": "unknown",
                    "shape": shape,
                    "runtime_proof": {"state": "not-joined"},
                })
            for key, child in sorted(value.items(), key=lambda item: str(item[0]).casefold()):
                visit(
                    child,
                    [*path_pattern, str(key)],
                    [*json_pointer, str(key)],
                    layer_id,
                )
        elif isinstance(value, list):
            for index, child in enumerate(value):
                visit(
                    child,
                    [*path_pattern, "[]"],
                    [*json_pointer, str(index)],
                    layer_id,
                )

    for object_index, value in enumerate(objects):
        if isinstance(value, dict):
            visit(value, ["objects", "[]"], ["objects", str(object_index)], value.get("id"))
    general = root.get("general")
    if isinstance(general, dict):
        visit(general, ["general"], ["general"])
    return results


def _project_properties(
    *,
    sample_id: str,
    project: dict[str, Any],
    profiles: ParameterProfiles,
) -> list[dict[str, Any]]:
    general = project.get("general")
    properties = general.get("properties") if isinstance(general, dict) else None
    if not isinstance(properties, dict):
        return []
    occurrences = []
    for name, value in sorted(properties.items(), key=lambda item: str(item[0]).casefold()):
        location = {"sample_id": sample_id, "property_name": str(name)}
        identity = occurrence_id("project-property", location)
        shape = safe_value_shape(value)
        refs = []
        if isinstance(value, dict):
            refs = [
                profiles.add("project-property", str(key), child, identity)
                for key, child in sorted(value.items())
            ]
        occurrences.append({
            "occurrence_id": identity,
            "family_key": family_key(
                "project-property",
                str(value.get("type", "unknown")) if isinstance(value, dict) else "malformed",
                shape,
            ),
            "domain": "project-property",
            "kind": str(value.get("type", "unknown")) if isinstance(value, dict) else "malformed",
            "revision_key": canonical_sha256(value),
            "location": location,
            "effective_visibility": "not-applicable",
            "shape": shape,
            "parameter_profile_refs": sorted(set(refs)),
        })
    return occurrences


def _sample_census(
    sample: Path,
    stock_root: Path,
    matrix_ids: set[str],
    profiles: ParameterProfiles,
    schema: SchemaInventory,
) -> tuple[dict[str, Any], list[dict[str, Any]], list[dict[str, Any]], list[dict[str, Any]]]:
    sample_id = sample.name
    tree_sha, file_count, byte_count = tree_manifest(sample)
    project_path = sample / "project.json"
    base = {
        "sample_id": sample_id,
        "parse_state": "failed",
        "in_full_matrix": sample_id in matrix_ids,
        "runtime_evidence_state": "not-joined",
        "first_blocker": {"state": "unknown"},
        "next_blocker": {"state": "not-observable-until-retest"},
        "tree_sha256": tree_sha,
        "file_count": file_count,
        "byte_count": byte_count,
        "occurrence_refs": [],
        "visible_occurrence_refs": [],
        "diagnostics": [],
    }
    if not project_path.is_file():
        base["diagnostics"].append({"code": "project-json-missing"})
        return base, [], [], []
    try:
        project = decode_json(project_path.read_bytes())
    except ValueError as error:
        base["diagnostics"].append({"code": str(error)})
        return base, [], [], []
    if not isinstance(project, dict):
        base["diagnostics"].append({"code": "project-root-not-object"})
        return base, [], [], []
    schema.add_document("project", project, sample_id)
    project_type = project.get("type")
    if not isinstance(project_type, str) or project_type.strip().casefold() != "scene":
        base["diagnostics"].append({"code": "project-type-not-scene"})
        return base, [], [], []
    entry_name, preferred_package = project_package_name(project)
    package_path = sample / preferred_package
    if not package_path.is_file() and preferred_package != "scene.pkg":
        fallback = sample / "scene.pkg"
        package_path = fallback if fallback.is_file() else package_path
    base.update({
        "title": project_title_metadata(project.get("title"), sample_id),
        "project_type": project_type,
        "entry_path": entry_name,
        "package_file": package_path.name,
        "project_sha256": sha256_file(project_path),
        "package_sha256": sha256_file(package_path) if package_path.is_file() else None,
        "package_byte_count": package_path.stat().st_size if package_path.is_file() else 0,
        "preview_file": project.get("preview") if isinstance(project.get("preview"), str) else None,
        "has_manual_screenshot": any(
            path.is_file() and path.suffix.casefold() == ".png" and path.name.startswith("截屏")
            for path in sample.iterdir()
        ),
        "has_user_observation": (sample / "用户观察说明.md").is_file(),
    })
    if not package_path.is_file():
        base["diagnostics"].append({"code": "package-missing"})
        return base, [], [], []

    occurrences: list[dict[str, Any]] = []
    textures: list[dict[str, Any]] = []
    unclassified: list[dict[str, Any]] = []
    with PkgArchive(package_path) as archive:
        base["package_magic"] = archive.magic
        base["package_entry_count"] = len(archive.entries)
        base["package_unique_path_count"] = len({path_identity(entry.path) for entry in archive.entries})
        base["package_categories"] = dict(sorted(Counter(
            package_category(entry.path) for entry in archive.entries
        ).items()))
        base["diagnostics"].extend(archive.diagnostics)
        observed_json: set[tuple[str, str, int | None]] = set()

        def observe_json(resource: ResolvedResource, value: Any) -> None:
            identity = (
                resource.origin,
                path_identity(resource.relative_path),
                resource.entry.index if resource.entry is not None else None,
            )
            if identity in observed_json:
                return
            observed_json.add(identity)
            schema.add_document(
                json_document_kind(resource.relative_path, entry_name),
                value,
                sample_id,
            )

        entry_matches = archive.matches(entry_name)
        if len(entry_matches) != 1:
            base["diagnostics"].append({
                "code": "entry-cardinality-mismatch",
                "count": len(entry_matches),
            })
            return base, [], [], []
        entry = entry_matches[0]
        try:
            scene = decode_json(archive.read_entry(entry) or b"")
        except ValueError as error:
            base["diagnostics"].append({"code": str(error)})
            return base, [], [], []
        if not isinstance(scene, dict):
            base["diagnostics"].append({"code": "scene-root-not-object"})
            return base, [], [], []
        base["scene_entry_sha256"] = archive.entry_sha256(entry)
        base["scene_entry_byte_count"] = entry.size
        view = SceneResourceView(
            sample,
            stock_root,
            archive,
            json_observer=observe_json,
        )
        package_resources, package_resource_diagnostics = census_package_resources(
            sample_id=sample_id,
            archive=archive,
            observe_json=observe_json,
            view=view,
        )
        occurrences.extend(package_resources)
        base["diagnostics"].extend(package_resource_diagnostics)
        objects = scene.get("objects") if isinstance(scene.get("objects"), list) else []
        layer_visibilities = authored_layer_visibilities(objects)
        base["object_count"] = len(objects)
        object_counts = Counter()
        visible_object_counts = Counter()
        dynamic_counts: dict[str, int] = {}
        effect_count = 0
        particle_layer_count = 0
        for object_index, layer in enumerate(objects):
            if not isinstance(layer, dict):
                unclassified.append({
                    "domain": "scene-object",
                    "location": {"sample_id": sample_id, "object_index": object_index},
                    "field": "object",
                    "value_shape": safe_value_shape(layer),
                })
                continue
            kind = object_kind(layer)
            object_counts[kind] += 1
            visibility = layer_visibilities[object_index]
            if visibility != "hidden":
                visible_object_counts[kind] += 1
            merge_counts(dynamic_counts, recursive_dynamic_features(layer))
            object_location = {
                "sample_id": sample_id,
                "layer_id": layer.get("id"),
                "object_index": object_index,
            }
            object_id = occurrence_id("layer-object", object_location)
            object_profile_refs = _object_parameters(
                profiles, sample_id, object_index, layer, object_id
            )
            layer_shape = {
                "kind": kind,
                "keys": sorted(layer),
                "has_parent": isinstance(layer.get("parent"), int),
                "dependency_count": len(layer.get("dependencies") or [])
                if isinstance(layer.get("dependencies"), list) else 0,
                "effect_count": len(layer.get("effects") or [])
                if isinstance(layer.get("effects"), list) else 0,
            }
            occurrences.append({
                "occurrence_id": object_id,
                "family_key": family_key("layer", kind, layer_shape),
                "revision_key": revision_key(layer),
                "domain": "layer",
                "kind": kind,
                "location": object_location,
                "effective_visibility": visibility,
                "parameter_profile_refs": sorted(set(object_profile_refs)),
            })
            image_occurrences, image_textures, image_unknown = census_image_layer(
                sample_id=sample_id,
                object_index=object_index,
                layer=layer,
                view=view,
                profiles=profiles,
                layer_visibility=visibility,
            )
            occurrences.extend(image_occurrences)
            textures.extend(image_textures)
            unclassified.extend(image_unknown)
            if isinstance(layer.get("particle"), str):
                particle_layer_count += 1
                particle_occurrences, particle_textures, particle_unknown = census_particle_layer(
                    sample_id=sample_id,
                    object_index=object_index,
                    layer=layer,
                    view=view,
                    profiles=profiles,
                    layer_visibility=visibility,
                )
                occurrences.extend(particle_occurrences)
                textures.extend(particle_textures)
                unclassified.extend(particle_unknown)
            for effect_index, effect in enumerate(layer.get("effects") or []):
                if not isinstance(effect, dict):
                    unclassified.append({
                        "domain": "effect-instance",
                        "location": {**object_location, "effect_index": effect_index},
                        "field": "effect",
                        "value_shape": safe_value_shape(effect),
                    })
                    continue
                effect_count += 1
                effect_occurrences, effect_textures, effect_unknown = census_effect(
                    sample_id=sample_id,
                    object_index=object_index,
                    layer=layer,
                    effect_index=effect_index,
                    effect=effect,
                    view=view,
                    profiles=profiles,
                    layer_visibility=visibility,
                )
                occurrences.extend(effect_occurrences)
                textures.extend(effect_textures)
                unclassified.extend(effect_unknown)
        dynamic_occurrences = _dynamic_occurrences(
            sample_id=sample_id,
            root=scene,
            objects=objects,
        )
        property_occurrences = _project_properties(
            sample_id=sample_id,
            project=project,
            profiles=profiles,
        )
        occurrences.extend(dynamic_occurrences)
        occurrences.extend(property_occurrences)
        base.update({
            "parse_state": "parsed",
            "object_kind_counts": dict(sorted(object_counts.items())),
            "visible_object_kind_counts": dict(sorted(visible_object_counts.items())),
            "effect_instance_count": effect_count,
            "particle_layer_count": particle_layer_count,
            "dynamic_feature_counts": dict(sorted(dynamic_counts.items())),
        })

    all_occurrences = [*occurrences, *textures]
    base["occurrence_refs"] = sorted(item["occurrence_id"] for item in all_occurrences)
    base["visible_occurrence_refs"] = sorted(
        item["occurrence_id"]
        for item in all_occurrences
        if item.get("effective_visibility") in {"visible", "dynamic"}
    )
    base["domain_counts"] = dict(sorted(Counter(item["domain"] for item in all_occurrences).items()))
    base["unclassified_count"] = len(unclassified)
    return base, occurrences, textures, unclassified


def _family_rollup(
    occurrences: list[dict[str, Any]],
    ledger: dict[str, Any],
) -> list[dict[str, Any]]:
    repair_by_family = {
        str(item["family_key"]): item
        for item in ledger.get("families", [])
        if isinstance(item, dict) and isinstance(item.get("family_key"), str)
    }
    grouped: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for occurrence in occurrences:
        grouped[occurrence["family_key"]].append(occurrence)
    result = []
    for key, values in sorted(grouped.items()):
        sample_ids = sorted({str(item["location"].get("sample_id")) for item in values})
        visible_values = [
            item for item in values
            if item.get("effective_visibility") in {"visible", "dynamic"}
        ]
        row = {
            "family_key": key,
            "domain": values[0]["domain"],
            "kind": values[0]["kind"],
            "occurrence_count": len(values),
            "sample_count": len(sample_ids),
            "sample_ids": sample_ids,
            "visible_occurrence_count": len(visible_values),
            "visible_sample_count": len({
                str(item["location"].get("sample_id")) for item in visible_values
            }),
            "revision_count": len({
                item.get("revision_key") for item in values if item.get("revision_key")
            }),
            "repair": repair_by_family.get(key, {"repair_state": "untriaged"}),
            "feature_summary": _family_feature_summary(values),
        }
        result.append(row)
    return result


def _family_feature_summary(values: list[dict[str, Any]]) -> dict[str, Any]:
    allowed = (
        "state", "slot_state", "provenance", "target_kind", "compose", "format", "uvs",
        "component_name", "parameter_keys", "combo_keys", "constant_keys", "render_state",
        "shader_features",
    )
    summary: dict[str, Any] = {}
    for field in allowed:
        variants = {
            json.dumps(value[field], ensure_ascii=False, sort_keys=True, separators=(",", ":"))
            for value in values
            if field in value
        }
        if variants:
            summary[field] = [json.loads(value) for value in sorted(variants)[:32]]
    return summary


def load_repair_ledger(path: Path) -> dict[str, Any]:
    if not path.is_file():
        return {
            "schema_version": 1,
            "status_contract": REPAIR_STATUS_CONTRACT,
            "families": [],
        }
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict) or payload.get("schema_version") != 1:
        raise ValueError("repair ledger schema must be 1")
    if not isinstance(payload.get("families"), list):
        raise ValueError("repair ledger families must be an array")
    if "status_contract" not in payload:
        payload["status_contract"] = REPAIR_STATUS_CONTRACT
    return payload


def validate_repair_ledger(
    ledger: dict[str, Any],
    observed_family_keys: set[str],
) -> list[dict[str, Any]]:
    failures: list[dict[str, Any]] = []
    status_contract = {field: set(values) for field, values in REPAIR_STATUS_CONTRACT.items()}
    declared_contract = ledger.get("status_contract")
    for field, allowed in status_contract.items():
        declared = declared_contract.get(field) if isinstance(declared_contract, dict) else None
        if not isinstance(declared, list) or set(declared) != allowed or len(declared) != len(allowed):
            failures.append({"code": "repair-status-contract-invalid", "field": field})
    seen: set[str] = set()
    for index, item in enumerate(ledger.get("families", [])):
        if not isinstance(item, dict):
            failures.append({"code": "repair-entry-not-object", "index": index})
            continue
        key = item.get("family_key")
        if not isinstance(key, str):
            failures.append({"code": "repair-family-key-missing", "index": index})
            continue
        if key in seen:
            failures.append({"code": "duplicate-repair-family", "family_key": key})
        seen.add(key)
        item["corpus_observation_state"] = (
            "observed" if key in observed_family_keys else "historical-not-currently-observed"
        )
        repair_state = item.get("repair_state")
        runtime_state = item.get("runtime_proof_state")
        regression_state = item.get("regression_protection_state")
        gates = item.get("regression_gates")
        events = item.get("events")
        for field, allowed in status_contract.items():
            if item.get(field) not in allowed:
                failures.append({
                    "code": "repair-state-invalid",
                    "family_key": key,
                    "field": field,
                    "value": item.get(field),
                })
        if repair_state == "bounded-verified":
            if runtime_state not in {"visible-chain-closed", "official-golden-equivalent"}:
                failures.append({"code": "verified-repair-lacks-visible-proof", "family_key": key})
            if regression_state not in {"targeted-runtime", "milestone"}:
                failures.append({
                    "code": "verified-repair-lacks-targeted-regression-protection",
                    "family_key": key,
                })
            required_gate_kinds = {
                "synthetic-positive", "synthetic-negative", "targeted-runtime",
            }
            gate_kinds = {
                gate.get("kind")
                for gate in gates or []
                if isinstance(gate, dict)
                and isinstance(gate.get("kind"), str)
                and isinstance(gate.get("reference"), str)
                and gate["reference"].strip()
            } if isinstance(gates, list) else set()
            if not required_gate_kinds.issubset(gate_kinds):
                failures.append({
                    "code": "verified-repair-lacks-regression-gates",
                    "family_key": key,
                    "missing_kinds": sorted(required_gate_kinds - gate_kinds),
                })
            if not isinstance(events, list) or not events:
                failures.append({"code": "verified-repair-lacks-event", "family_key": key})
            else:
                required_event_fields = {"date", "state", "commit", "evidence_refs", "notes"}
                for event_index, event in enumerate(events):
                    valid_event = (
                        isinstance(event, dict)
                        and not required_event_fields.difference(event)
                        and event.get("state") in status_contract["repair_state"]
                        and isinstance(event.get("evidence_refs"), list)
                        and bool(event["evidence_refs"])
                        and all(
                            isinstance(event.get(field), str) and event[field].strip()
                            for field in ("date", "commit", "notes")
                        )
                        and all(
                            isinstance(reference, str) and reference.strip()
                            for reference in event["evidence_refs"]
                        )
                    )
                    if not valid_event:
                        failures.append({
                            "code": "verified-repair-event-invalid",
                            "family_key": key,
                            "event_index": event_index,
                        })
            required = {
                "root_cause", "public_fix", "commit", "targeted_samples",
                "roi_evidence", "remaining_boundaries",
            }
            missing = sorted(field for field in required if not item.get(field))
            if missing:
                failures.append({
                    "code": "verified-repair-missing-fields",
                    "family_key": key,
                    "fields": missing,
                })
            for field in ("targeted_samples", "roi_evidence", "remaining_boundaries"):
                values = item.get(field)
                if not isinstance(values, list) or not values or not all(
                    isinstance(value, str) and value.strip() for value in values
                ):
                    failures.append({
                        "code": "verified-repair-field-invalid",
                        "family_key": key,
                        "field": field,
                    })
            for field in ("root_cause", "public_fix", "commit"):
                if not isinstance(item.get(field), str) or not item[field].strip():
                    failures.append({
                        "code": "verified-repair-field-invalid",
                        "family_key": key,
                        "field": field,
                    })
        if runtime_state == "official-golden-equivalent" and not item.get("official_golden_refs"):
            failures.append({"code": "official-equivalence-lacks-golden", "family_key": key})
        if runtime_state == "official-golden-equivalent":
            for field in ("official_phase_identity", "pixel_tolerance", "timing_tolerance"):
                if not item.get(field):
                    failures.append({
                        "code": "official-equivalence-missing-contract",
                        "family_key": key,
                        "field": field,
                    })
    return failures


def build_census(
    samples_root: Path,
    stock_root: Path,
    matrix_path: Path,
    ledger_path: Path,
) -> dict[str, Any]:
    samples_root = samples_root.expanduser().resolve()
    stock_root = stock_root.expanduser().resolve()
    if not samples_root.is_dir():
        raise FileNotFoundError(samples_root)
    if not stock_root.is_dir():
        raise FileNotFoundError(stock_root)
    samples = list(iter_numeric_sample_directories(samples_root))
    matrix = matrix_identity(matrix_path)
    matrix_ids = set(matrix.get("sample_ids", []))
    profiles = ParameterProfiles()
    schema = SchemaInventory()
    sample_rows: list[dict[str, Any]] = []
    occurrences: list[dict[str, Any]] = []
    textures: list[dict[str, Any]] = []
    unclassified: list[dict[str, Any]] = []
    for sample in samples:
        row, sample_occurrences, sample_textures, sample_unknown = _sample_census(
            sample,
            stock_root,
            matrix_ids,
            profiles,
            schema,
        )
        sample_rows.append(row)
        occurrences.extend(sample_occurrences)
        textures.extend(sample_textures)
        unclassified.extend(sample_unknown)

    all_occurrences = sorted(
        [*occurrences, *textures],
        key=lambda value: value["occurrence_id"],
    )
    occurrence_ids = [item["occurrence_id"] for item in all_occurrences]
    duplicate_occurrences = sorted(
        identity for identity, count in Counter(occurrence_ids).items() if count > 1
    )
    occurrence_id_set = set(occurrence_ids)
    parameter_payloads = profiles.payloads()
    parameter_refs = [
        reference
        for profile in parameter_payloads
        for reference in profile["occurrence_refs"]
    ]
    orphan_parameter_refs = sorted(set(parameter_refs) - occurrence_id_set)
    missing_revision_ids = sorted(
        item["occurrence_id"] for item in all_occurrences if not item.get("revision_key")
    )
    texture_visibility_failures = sorted(
        item["occurrence_id"]
        for item in all_occurrences
        if item["domain"] == "texture"
        and item["kind"] != "package-resource"
        and item.get("effective_visibility") not in {"visible", "dynamic", "hidden", "unknown"}
    )
    graph_binding_state_failures = sorted(
        item["occurrence_id"]
        for item in all_occurrences
        if item["domain"] == "texture"
        and item["kind"] == "graph-binding"
        and item.get("slot_state") not in {"runtime-provided", "hole"}
    )
    family_namespace_failures = sorted(
        item["occurrence_id"]
        for item in all_occurrences
        if not item["family_key"].startswith(f"{item['domain']}/")
    )
    ledger = load_repair_ledger(ledger_path)
    family_keys = {item["family_key"] for item in all_occurrences}
    ledger_failures = validate_repair_ledger(ledger, family_keys)
    schema_conservation = schema.conservation()
    parsed_count = sum(row["parse_state"] == "parsed" for row in sample_rows)
    failed_count = len(sample_rows) - parsed_count
    discovered_ids = [sample.name for sample in samples]
    added = sorted(set(discovered_ids) - matrix_ids)
    removed = sorted(matrix_ids - set(discovered_ids))
    texture_occurrences = [
        item for item in all_occurrences if item["domain"] == "texture"
    ]
    physical_textures = [
        item for item in texture_occurrences if item["kind"] == "package-resource"
    ]
    texture_uses = [
        item for item in texture_occurrences if item["kind"] != "package-resource"
    ]
    package_resource_occurrences = [
        item
        for item in all_occurrences
        if "package_entry_index" in item["location"]
    ]
    object_kind_counts: Counter[str] = Counter()
    visible_object_kind_counts: Counter[str] = Counter()
    package_category_counts: Counter[str] = Counter()
    dynamic_feature_counts: Counter[str] = Counter()
    for row in sample_rows:
        object_kind_counts.update(row.get("object_kind_counts", {}))
        visible_object_kind_counts.update(row.get("visible_object_kind_counts", {}))
        package_category_counts.update(row.get("package_categories", {}))
        dynamic_feature_counts.update(row.get("dynamic_feature_counts", {}))
    physical_tex_formats = Counter(
        str(item["tex"]["format_code"])
        for item in physical_textures
        if isinstance(item.get("tex"), dict) and item["tex"].get("state") == "parsed"
    )
    physical_tex_features = Counter()
    for item in physical_textures:
        tex = item.get("tex") or {}
        if tex.get("state") != "parsed":
            physical_tex_features["malformed"] += 1
            continue
        physical_tex_features["animated" if tex.get("is_animated") else "static"] += 1
        if tex.get("is_volume"):
            physical_tex_features["volume"] += 1
        if tex.get("is_video_mp4"):
            physical_tex_features["video-mp4"] += 1
    total_package_entries = sum(int(row.get("package_entry_count", 0)) for row in sample_rows)
    total_unique_package_paths = sum(
        int(row.get("package_unique_path_count", 0)) for row in sample_rows
    )
    failures = []
    if duplicate_occurrences:
        failures.append({"code": "duplicate-occurrence-identity", "occurrence_ids": duplicate_occurrences})
    if not schema_conservation["balanced"]:
        failures.append({"code": "schema-leaf-conservation-failed"})
    if total_package_entries != len(package_resource_occurrences):
        failures.append({"code": "package-resource-conservation-failed"})
    if orphan_parameter_refs:
        failures.append({
            "code": "parameter-occurrence-reference-orphaned",
            "occurrence_ids": orphan_parameter_refs,
        })
    if missing_revision_ids:
        failures.append({
            "code": "occurrence-revision-missing",
            "occurrence_ids": missing_revision_ids,
        })
    if texture_visibility_failures:
        failures.append({
            "code": "texture-use-visibility-missing",
            "occurrence_ids": texture_visibility_failures,
        })
    if graph_binding_state_failures:
        failures.append({
            "code": "graph-binding-misclassified-as-asset",
            "occurrence_ids": graph_binding_state_failures,
        })
    if family_namespace_failures:
        failures.append({
            "code": "family-domain-namespace-mismatch",
            "occurrence_ids": family_namespace_failures,
        })
    failures.extend(ledger_failures)
    stock_sha, stock_files, stock_bytes = directory_manifest(stock_root)
    result = {
        "schema_version": 1,
        "kind": "scene-capability-census",
        "snapshot": {
            "generator": {
                "path": relative_repo_path(Path(__file__)),
                "source_manifest": generator_manifest(),
                "canonical_json_contract": "sorted-keys-indented-utf8-v1",
            },
            "inputs": {
                "sample_root_label": "Workshop/Scene",
                "sample_id_manifest_sha256": corpus_manifest(samples),
                "stock_root_manifest_sha256": stock_sha,
                "stock_file_count": stock_files,
                "stock_byte_count": stock_bytes,
                "full_matrix": matrix,
                "repair_ledger": {
                    "relative_path": relative_repo_path(ledger_path),
                    "sha256": sha256_file(ledger_path) if ledger_path.is_file() else None,
                },
            },
            "boundaries": [
                "authored static observation never implies runtime support",
                "runtime evidence is not joined by this static census",
                "sample and layer identities are evidence locators, not product dispatch",
                "project title metadata is retained; layer text and shader, script, JSON fragment, texture, and binary payloads are not retained",
                "official visual equivalence requires a separate same-phase golden",
            ],
        },
        "summary": {
            "discovered_sample_count": len(samples),
            "parsed_sample_count": parsed_count,
            "failed_sample_count": failed_count,
            "matrix_sample_count": len(matrix_ids),
            "matrix_coverage_state": "current" if not added and not removed else "pending-expansion",
            "added_since_matrix": added,
            "removed_since_matrix": removed,
            "occurrence_count": len(all_occurrences),
            "package_entry_count": total_package_entries,
            "package_unique_path_count": total_unique_package_paths,
            "package_byte_count": sum(int(row.get("package_byte_count", 0)) for row in sample_rows),
            "package_category_counts": dict(sorted(package_category_counts.items())),
            "project_type_counts": dict(sorted(Counter(
                str(row.get("project_type")) for row in sample_rows if row.get("project_type")
            ).items())),
            "scene_entry_counts": dict(sorted(Counter(
                str(row.get("entry_path")) for row in sample_rows if row.get("entry_path")
            ).items())),
            "object_kind_counts": dict(sorted(object_kind_counts.items())),
            "visible_object_kind_counts": dict(sorted(visible_object_kind_counts.items())),
            "effect_instance_count": sum(int(row.get("effect_instance_count", 0)) for row in sample_rows),
            "particle_layer_count": sum(int(row.get("particle_layer_count", 0)) for row in sample_rows),
            "dynamic_feature_counts": dict(sorted(dynamic_feature_counts.items())),
            "occurrences_by_domain": dict(sorted(Counter(
                item["domain"] for item in all_occurrences
            ).items())),
            "family_count": len(family_keys),
            "families_by_domain": dict(sorted(Counter(
                item["domain"] for item in _family_rollup(all_occurrences, ledger)
            ).items())),
            "parameter_profile_count": len(parameter_payloads),
            "schema_field_profile_count": len(schema.payloads()),
            "unclassified_count": len(unclassified),
            "generic_or_unknown_family_count": sum(
                any(token in item["kind"].casefold() for token in ("unknown", "unresolved", "malformed"))
                for item in _family_rollup(all_occurrences, ledger)
            ),
            "package_anomaly_count": sum(len(row["diagnostics"]) for row in sample_rows),
            "texture": {
                "physical_resource_count": len(physical_textures),
                "physical_format_counts": dict(sorted(physical_tex_formats.items())),
                "physical_feature_counts": dict(sorted(physical_tex_features.items())),
                "use_occurrence_count": len(texture_uses),
                "use_state_counts": dict(sorted(Counter(
                    str(item.get("slot_state", "unknown")) for item in texture_uses
                ).items())),
                "all": summarize_texture_families(texture_occurrences),
            },
            "particle": particle_summary([
                item for item in all_occurrences if item["domain"] == "particle"
            ]),
        },
        "samples": sorted(sample_rows, key=lambda value: value["sample_id"]),
        "families": _family_rollup(all_occurrences, ledger),
        "occurrences": all_occurrences,
        "parameter_profiles": parameter_payloads,
        "schema_fields": schema.payloads(),
        "unclassified": sorted(unclassified, key=canonical_sha256),
        "repair_ledger": ledger,
        "validation": {
            "failures": failures,
            "conservation": {
                "samples": {
                    "discovered": len(samples),
                    "parsed_plus_failed": parsed_count + failed_count,
                    "balanced": len(samples) == parsed_count + failed_count,
                },
                "sample_occurrence_refs": sum(len(row["occurrence_refs"]) for row in sample_rows),
                "global_occurrence_count": len(all_occurrences),
                "occurrences_balanced": (
                    sum(len(row["occurrence_refs"]) for row in sample_rows) == len(all_occurrences)
                ),
                "schema_fields": schema_conservation,
                "package_resources": {
                    "package_entries": total_package_entries,
                    "resource_occurrences": len(package_resource_occurrences),
                    "balanced": total_package_entries == len(package_resource_occurrences),
                },
                "parameter_occurrence_refs": {
                    "classified": len(parameter_refs),
                    "orphan_count": len(orphan_parameter_refs),
                    "balanced": not orphan_parameter_refs,
                },
                "revisions": {
                    "occurrence_count": len(all_occurrences),
                    "missing_count": len(missing_revision_ids),
                    "balanced": not missing_revision_ids,
                },
                "texture_use_visibility": {
                    "use_count": len(texture_uses),
                    "missing_count": len(texture_visibility_failures),
                    "balanced": not texture_visibility_failures,
                },
            },
            "determinism": {
                "sort_contract": "all IDs, paths, families, occurrences, profiles and diagnostics canonical",
                "payload_sha256": None,
            },
        },
    }
    digest_input = json.loads(json.dumps(result, ensure_ascii=False))
    digest_input["validation"]["determinism"]["payload_sha256"] = None
    result["validation"]["determinism"]["payload_sha256"] = canonical_sha256(digest_input)
    return result


def render_markdown(census: dict[str, Any]) -> str:
    summary = census["summary"]
    samples = census["samples"]
    family_rows = sorted(
        census["families"],
        key=lambda value: (
            -value["visible_sample_count"],
            -value["sample_count"],
            -value["visible_occurrence_count"],
            value["family_key"],
        ),
    )
    domain_rows = Counter(item["domain"] for item in census["occurrences"])
    family_domains = Counter(item["domain"] for item in census["families"])
    package_anomalies = [
        (sample, diagnostic)
        for sample in samples
        for diagnostic in sample.get("diagnostics", [])
        if diagnostic.get("code") == "duplicate-package-path"
    ]
    anomaly_lines = []
    for sample, diagnostic in package_anomalies:
        indices = "/".join(str(value) for value in diagnostic.get("entry_indices", []))
        equality = "同字节" if diagnostic.get("content_equal") else "不同字节"
        anomaly_lines.append(
            f"样本 `{sample['sample_id']}` 的 `{diagnostic.get('path', 'unknown')}` "
            f"entry重复（indices {indices}，{equality}；该包 "
            f"{sample['package_entry_count']} entries / "
            f"{sample['package_unique_path_count']} unique paths）"
        )
    anomaly_summary = "；".join(anomaly_lines) or "无"
    lines = [
        "# Scene 全样本能力分类与修复台账",
        "",
        "> 状态：现役 corpus 事实与公共修复候选索引。",
        ">",
        "> 本页由 `script/scene_capability_census.py` 从只读 authored corpus 生成；完整 family、样本归属、参数/字段 profile、compact layer/pass/slot occurrence index 与守恒摘要在 `script/scene_capability_census_snapshot.json`。资源 identity 和详细 owner 事实仅在显式 `query --live` 时从私有 corpus 重建。能力等级仍以专项表为准，App/GPU/ROI 证据仍以 `runtime-evidence-index.md` 为准。",
        "",
        "## 1. 当前结论",
        "",
        f"- 当前真实 Scene 根发现 **{summary['discovered_sample_count']}** 个样本，**{summary['parsed_sample_count']}/{summary['discovered_sample_count']}** 的 project、PKGV 索引和入口 JSON 可解析。",
        f"- tracked full-matrix baseline 当前覆盖 **{summary['matrix_sample_count']}** 个历史成员，状态为 `{summary['matrix_coverage_state']}`；本 census 新发现但未 join 运行证据的样本为 `{', '.join(summary['added_since_matrix']) or '无'}`，是否曾单独运行不能由静态扫描判断。",
        f"- 全量 authored census 共保存 **{summary['occurrence_count']}** 个 typed occurrence、**{summary['family_count']}** 个公共结构 family、**{summary['parameter_profile_count']}** 个参数 profile 与 **{summary['schema_field_profile_count']}** 个 JSON 字段 profile。",
        f"- 物理 corpus 共 **{summary['package_entry_count']}** 个 PKG entry / **{summary['package_unique_path_count']}** 个唯一路径，包体约 **{summary['package_byte_count'] / 1_000_000_000:.3f} GB**；tracked baseline 在单独的 milestone 扩容并建立运行期待前仍为 {summary['matrix_sample_count']}，期间不得称为当前完整快照门。",
        f"- package anomaly：{anomaly_summary}；重复entry继续保留在物理守恒中，不是漏扫。",
        f"- 结构 fallback 记录为 **{summary['unclassified_count']}**，另有 **{summary['generic_or_unknown_family_count']}** 个 generic/unknown/unresolved family；两者都不是运行失败数。本 census 未 join 运行证据的样本，其第一 blocker 保持 `unknown`，不得从静态形态猜测。",
        "- 开发按“真实可见链第一断裂边覆盖的共享 family”排序；大类用于汇总，不允许把所有纹理、Effect 或粒子一次性做成巨型补丁。",
        "",
        "## 2. 口径与权威边界",
        "",
        "1. 本 census 回答样本声明了什么：对象、Effect/Material/Shader/Graph/FBO、纹理、粒子、动态来源和参数形态。",
        "2. `observed`、`resolved` 或文件存在不等于 renderer 已支持；运行 owner、GPU、publication、compositor、next-frame 和 ROI 必须引用运行证据索引。",
        "3. `family_key` 只由公共语义形态生成；sample/layer/path/hash 只作 evidence identity，产品实现不得按具体值 dispatch。",
        "4. 所有参数以名称、类型、arity、范围、wrapper source 和结构签名记录；只保留 project title 元数据，不复制 layer 文字、shader、SceneScript、纹理、JSON 片段或二进制 payload。",
        "5. 修好一族后在 `scene_capability_repair_ledger.json` 记录根因、公共修法、commit、正反门、真实样本、ROI、剩余边界；重新扫描不会覆盖历史。",
        "6. 先以官方公开资料和当前 corpus 界定作者合同；只有公开材料不足、固定客户端静态证据仍不能回答 producer-to-consumer 链，或需要交叉核对结构时，才读取 MirageWallpaper 的明确固定 revision 并记录 divergence。Mirage 只提供 clean-room 的职责、状态流和顺序参考；其 GPL 源码、shader、资产、payload、常量组合、算法表达和测试数据不得进入项目。",
        "",
        "## 3. 大类总览",
        "",
        "| 大类 | occurrence | family | 现役能力事实入口 |",
        "|---|---:|---:|---|",
    ]
    authorities = {
        "resource": "[格式/资源](scene-format-and-render-graph.md)",
        "shader": "[Graph/Shader](render-graph-shader-coverage.md)",
        "layer": "[格式/对象](scene-format-and-render-graph.md)",
        "material": "[Graph/Shader](render-graph-shader-coverage.md)",
        "effect": "[Effect](effect-execution-coverage.md)",
        "render-graph": "[Graph/Shader](render-graph-shader-coverage.md)",
        "render-target": "[Graph/Shader](render-graph-shader-coverage.md)",
        "texture": "[格式/资源](scene-format-and-render-graph.md) / [Graph/Shader](render-graph-shader-coverage.md) / [Provider](runtime-input-property-coverage.md)",
        "particle": "[粒子](particle-component-coverage.md)",
        "dynamic-input": "[属性/输入](runtime-input-property-coverage.md)",
        "project-property": "[属性/输入](runtime-input-property-coverage.md)",
    }
    for domain in DOMAINS:
        lines.append(
            f"| `{domain}` | {domain_rows.get(domain, 0)} | {family_domains.get(domain, 0)} | {authorities[domain]} |"
        )
    texture = summary["texture"]
    lines += [
        "",
        "### 3.1 纹理本体与使用点",
        "",
        f"- 包内物理 TEX：**{texture['physical_resource_count']}**；格式分布：`{json.dumps(texture['physical_format_counts'], ensure_ascii=False, sort_keys=True)}`。",
        f"- TEX 结构特征：`{json.dumps(texture['physical_feature_counts'], ensure_ascii=False, sort_keys=True)}`。这些只证明文件结构可读，不证明上传、purpose、sampler 或合成正确。",
        f"- 纹理使用 occurrence：**{texture['use_occurrence_count']}**；slot 状态：`{json.dumps(texture['use_state_counts'], ensure_ascii=False, sort_keys=True)}`。`runtime-provided` 是 graph/named target 等运行身份，`missing` 需要结合 default/optional combo/VFS 语义判断，不能一律当缺图。",
        "",
        "### 3.2 对象、Effect 与动态输入",
        "",
        f"- 对象类型：`{json.dumps(summary['object_kind_counts'], ensure_ascii=False, sort_keys=True)}`；静态非 hidden：`{json.dumps(summary['visible_object_kind_counts'], ensure_ascii=False, sort_keys=True)}`。",
        f"- Effect instance **{summary['effect_instance_count']}**，粒子 root layer **{summary['particle_layer_count']}**；动态 wrapper：`{json.dumps(summary['dynamic_feature_counts'], ensure_ascii=False, sort_keys=True)}`。",
        f"- 粒子组件分布完整保存在机器快照 `summary.particle.component_counts`；Effect/Graph/FBO、包内 shader uniform/annotation/combo、material authored combo/constant 与全部 JSON 字段可按 family/profile 查询。active/prepared shader variant 仍以专项 census 与运行证据为准。",
    ]
    lines += [
        "",
        "## 4. 当前公共 family 影响面索引",
        "",
        "> 这里只按静态可见覆盖排序，不能自动决定实施。真正开批前必须由 fresh 隔离运行确认第一断裂边；高频但位于链后段的 family 不得抢占当前可见首断点。",
        "",
        "| family | domain/kind | occurrence | 样本 | 可见 occurrence / 样本 | 修复状态 |",
        "|---|---|---:|---:|---:|---|",
    ]
    for family in family_rows[:80]:
        repair = family.get("repair") or {}
        lines.append(
            f"| `{family['family_key']}` | `{family['domain']}/{family['kind']}` | "
            f"{family['occurrence_count']} | {family['sample_count']} | "
            f"{family['visible_occurrence_count']} / {family['visible_sample_count']} | "
            f"`{repair.get('repair_state', 'untriaged')}` |"
        )
    lines += [
        "",
        "完整 family、payload-free feature summary、样本归属与 revision 数在机器快照中；此表故意只保留前 80 个高覆盖项，避免人类文档成为不可维护的 payload 转储。",
        "",
        "## 5. 全部样本清单",
        "",
        "| 样本 | 标题 | 对象 | Effect | 粒子层 | occurrence | 人工对照 | matrix/runtime |",
        "|---|---|---:|---:|---:|---:|---|---|",
    ]
    for sample in samples:
        title = (
            str(sample.get("title", sample["sample_id"]))
            .replace("&", "&amp;")
            .replace("<", "&lt;")
            .replace(">", "&gt;")
            .replace("|", "\\|")
        )
        manual = "截图+说明" if sample["has_manual_screenshot"] and sample["has_user_observation"] else "无"
        matrix_state = (
            f"tracked{summary['matrix_sample_count']} / census未join runtime"
            if sample["in_full_matrix"]
            else "新增 / census未join runtime"
        )
        lines.append(
            f"| `{sample['sample_id']}` | {title} | {sample.get('object_count', 0)} | "
            f"{sample.get('effect_instance_count', 0)} | {sample.get('particle_layer_count', 0)} | "
            f"{len(sample['occurrence_refs'])} | {manual} | {matrix_state} |"
        )
    lines += [
        "",
        "## 6. 修复记录与防回归合同",
        "",
        "每个公共 family 使用三个独立状态：",
        "",
        "- `repair_state`: `untriaged -> diagnosed -> in-progress -> implemented -> bounded-verified`；",
        "- `runtime_proof_state`: `none -> partial-chain -> visible-chain-closed -> official-golden-equivalent`；",
        "- `regression_protection_state`: `none -> synthetic -> targeted-runtime -> milestone`。",
        "",
        "`bounded-verified` 至少要求项目自有 synthetic 正例、反例、真实隔离样本 GPU→publication→compositor→next-frame→ROI 和明确剩余边界。`official-golden-equivalent` 还必须有同相位官方 golden 及像素/时序容差。只降低 rejection 数、只 non-black 或只加载资源不能写成修复完成。",
        "",
        "当前已逐族复核并登记的修复见机器 repair ledger 与下方状态表；未列 family 继续保持 `untriaged`，不会因 effect 名、路径或相邻 family 已修而自动升级。",
        "",
    ]
    repaired_families = sorted(
        (
            repair for repair in census["repair_ledger"].get("families", [])
            if repair.get("repair_state", "untriaged") != "untriaged"
        ),
        key=lambda repair: repair["family_key"],
    )
    lines += [
        "| family | 修复 / 运行 / 回归状态 | 公共修法 | 真实 sentinel | 剩余边界 |",
        "|---|---|---|---|---|",
    ]
    for repair in repaired_families:
        def markdown_cell(value: Any) -> str:
            return str(value).replace("\n", " ").replace("|", "\\|")

        status = " / ".join(
            markdown_cell(repair[key])
            for key in (
                "repair_state",
                "runtime_proof_state",
                "regression_protection_state",
            )
        )
        sentinels = ", ".join(
            f"`{markdown_cell(value)}`" for value in repair.get("targeted_samples", [])
        ) or "无"
        boundaries = "；".join(
            markdown_cell(value) for value in repair.get("remaining_boundaries", [])
        )
        lines.append(
            f"| `{repair['family_key']}` | `{status}` (`{markdown_cell(repair.get('commit', ''))}`) | "
            f"{markdown_cell(repair.get('public_fix', ''))} | {sentinels} | {boundaries} |"
        )
    if not repaired_families:
        lines.append("| _尚无已登记修复_ | - | - | - | - |")
    lines += [
        "",
        "## 7. 更新流程",
        "",
        "1. 新增/删除样本后先只读运行 corpus census，确认 `discovered = parsed + failed`、occurrence 与 JSON leaf 守恒。",
        "2. authored census 一旦发现样本增删，tracked full-matrix baseline 立即标为 `pending-expansion`，不得再称完整；新样本的运行状态先记为本 census 未 join，随后用独立 milestone 扩容批建立运行期待并更新 matrix。",
        "3. 从 fresh 隔离报告定位首个失败 identity，再按现役通用执行计划选择能让未见内容受益、可局部降级且可独立回滚的公共 primitive；不得把 family 名直接变成产品 dispatch。",
        "4. 先核对官方作者合同和现有固定证据；只有材料不足以解释 producer-to-consumer 结构时才按需固定 MirageWallpaper revision，并记录实际读取模块与 divergence。第三方参考不是每批前置，也不提供算法真值。",
        "5. 同批实现公共代码、synthetic 正反门和与声明相称的代表运行门；只有具体 fidelity 修复才强制真实 ROI。再写 repair event 和必要的专项文档，不建立样本专用分支，也不复制第三方算法或 payload。",
        "6. `targeted_samples` 与 `regression_gates` 是后续必须重跑的 sentinel 合同；触达同 family 或它依赖的 selection/Program/publication/composition 时必须执行，不能用新的 aggregate count 覆盖旧视觉正证。",
        "",
        "生成命令：",
        "",
        "```bash",
        "python3.12 script/scene_capability_census.py generate \\",
        "  --samples-root \"$HOME/Movies/MyWallpaperX/创意工坊/Scene\" \\",
        "  --snapshot script/scene_capability_census_snapshot.json \\",
        "  --markdown docs/scene/semantics/scene-corpus-capability-inventory.md",
        "python3.12 script/scene_capability_census.py verify \\",
        "  --samples-root \"$HOME/Movies/MyWallpaperX/创意工坊/Scene\" \\",
        "  --snapshot script/scene_capability_census_snapshot.json \\",
        "  --markdown docs/scene/semantics/scene-corpus-capability-inventory.md",
        "python3.12 script/scene_capability_census.py query \\",
        "  --family <family-key>",
        "# 需要当前私有 corpus 的详细 resource/owner 事实时显式追加 --live",
        "```",
    ]
    return "\n".join(lines)


def canonical_json_bytes(payload: dict[str, Any]) -> bytes:
    return (json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n").encode("utf-8")


def snapshot_payload(census: dict[str, Any]) -> dict[str, Any]:
    """Project the conserving in-memory census into a reviewable Git baseline."""
    samples = []
    for value in census["samples"]:
        row = dict(value)
        occurrence_refs = row.pop("occurrence_refs")
        visible_refs = row.pop("visible_occurrence_refs")
        row.update({
            "occurrence_count": len(occurrence_refs),
            "occurrence_index_sha256": canonical_sha256(occurrence_refs),
            "visible_occurrence_count": len(visible_refs),
            "visible_occurrence_index_sha256": canonical_sha256(visible_refs),
        })
        samples.append(row)

    sample_by_occurrence = {
        value["occurrence_id"]: str(value["location"].get("sample_id"))
        for value in census["occurrences"]
    }
    parameter_profiles = []
    for value in census["parameter_profiles"]:
        profile = dict(value)
        occurrence_refs = profile.pop("occurrence_refs")
        sample_ids = sorted({
            sample_by_occurrence[identity]
            for identity in occurrence_refs
            if identity in sample_by_occurrence
        })
        profile["occurrence_index_sha256"] = canonical_sha256(occurrence_refs)
        profile["sample_count"] = len(sample_ids)
        profile["sample_ids"] = sample_ids
        parameter_profiles.append(profile)

    occurrence_index = [
        {
            "occurrence_id": value["occurrence_id"],
            "family_key": value["family_key"],
            "revision_key": value.get("revision_key"),
            "domain": value["domain"],
            "kind": value["kind"],
            "sample_id": value["location"].get("sample_id"),
            "effective_visibility": value.get("effective_visibility"),
            "location": {
                key: value["location"][key]
                for key in (
                    "layer_id", "object_index", "effect_index", "definition_pass_index",
                    "material_pass_index", "slot_index", "fbo_index", "component_category",
                    "component_index", "package_entry_index", "property_name",
                )
                if key in value["location"]
            },
        }
        for value in census["occurrences"]
    ]
    return {
        "schema_version": census["schema_version"],
        "kind": census["kind"],
        "snapshot": census["snapshot"],
        "summary": census["summary"],
        "samples": samples,
        "families": census["families"],
        "parameter_profiles": parameter_profiles,
        "schema_fields": census["schema_fields"],
        "unclassified": census["unclassified"],
        "repair_ledger": census["repair_ledger"],
        "validation": {
            **census["validation"],
            "occurrence_index": {
                "count": len(occurrence_index),
                "sha256": canonical_sha256(occurrence_index),
                "storage": "compact-baseline-index",
                "items": occurrence_index,
            },
        },
    }


def generate(args: argparse.Namespace) -> int:
    outputs = [args.snapshot, args.markdown]
    ensure_outputs_outside_roots(outputs, [args.samples_root, args.stock_root])
    census = build_census(args.samples_root, args.stock_root, args.matrix, args.ledger)
    if census["validation"]["failures"]:
        print(json.dumps(census["validation"], ensure_ascii=False, indent=2), file=sys.stderr)
        return 1
    atomic_write(args.snapshot, canonical_json_bytes(snapshot_payload(census)))
    atomic_write(args.markdown, (render_markdown(census) + "\n").encode("utf-8"))
    print(json.dumps({
        "sample_count": census["summary"]["discovered_sample_count"],
        "occurrence_count": census["summary"]["occurrence_count"],
        "family_count": census["summary"]["family_count"],
        "added_since_matrix": census["summary"]["added_since_matrix"],
        "snapshot": str(args.snapshot),
        "markdown": str(args.markdown),
        "payload_sha256": census["validation"]["determinism"]["payload_sha256"],
    }, ensure_ascii=False, indent=2))
    return 0


def verify(args: argparse.Namespace) -> int:
    ensure_outputs_outside_roots([args.snapshot, args.markdown], [args.samples_root, args.stock_root])
    expected = build_census(args.samples_root, args.stock_root, args.matrix, args.ledger)
    failures = list(expected["validation"]["failures"])
    expected_snapshot = canonical_json_bytes(snapshot_payload(expected))
    expected_markdown = (render_markdown(expected) + "\n").encode("utf-8")
    if not args.snapshot.is_file() or args.snapshot.read_bytes() != expected_snapshot:
        failures.append({"code": "snapshot-drift", "path": str(args.snapshot)})
    if not args.markdown.is_file() or args.markdown.read_bytes() != expected_markdown:
        failures.append({"code": "markdown-drift", "path": str(args.markdown)})
    print(json.dumps({
        "passed": not failures,
        "sample_count": expected["summary"]["discovered_sample_count"],
        "payload_sha256": expected["validation"]["determinism"]["payload_sha256"],
        "failures": failures,
    }, ensure_ascii=False, indent=2))
    return 1 if failures else 0


def query(args: argparse.Namespace) -> int:
    if not any((args.family, args.sample, args.domain)):
        print("query requires --family, --sample, or --domain", file=sys.stderr)
        return 2
    live = getattr(args, "live", False)
    if live:
        census = build_census(args.samples_root, args.stock_root, args.matrix, args.ledger)
        if census["validation"]["failures"]:
            print(json.dumps(census["validation"], ensure_ascii=False, indent=2), file=sys.stderr)
            return 1
        candidates = census["occurrences"]
        source = "live-corpus"
    else:
        snapshot = getattr(
            args,
            "snapshot",
            REPOSITORY_ROOT / "script/scene_capability_census_snapshot.json",
        )
        try:
            stored = json.loads(snapshot.read_text(encoding="utf-8"))
            candidates = stored["validation"]["occurrence_index"]["items"]
        except (OSError, KeyError, TypeError, json.JSONDecodeError) as error:
            print(f"unable to query committed census snapshot: {error}", file=sys.stderr)
            return 1
        source = "committed-snapshot"
    matches = [
        value
        for value in candidates
        if (args.family is None or value["family_key"] == args.family)
        and (args.sample is None or str(value.get("sample_id") or value["location"].get("sample_id")) == args.sample)
        and (args.domain is None or value["domain"] == args.domain)
    ]
    print(json.dumps({
        "count": len(matches),
        "filters": {
            "family": args.family,
            "sample": args.sample,
            "domain": args.domain,
        },
        "source": source,
        "occurrences": matches,
    }, ensure_ascii=False, indent=2, sort_keys=True))
    return 0


def parse_args(argv: Iterable[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    for command, handler in (("generate", generate), ("verify", verify), ("query", query)):
        subparser = subparsers.add_parser(command)
        subparser.add_argument("--samples-root", type=Path, default=DEFAULT_SAMPLES_ROOT)
        subparser.add_argument("--stock-root", type=Path, default=DEFAULT_STOCK_ROOT)
        subparser.add_argument("--matrix", type=Path, default=DEFAULT_MATRIX)
        subparser.add_argument("--ledger", type=Path, default=DEFAULT_LEDGER)
        if command != "query":
            subparser.add_argument(
                "--snapshot",
                type=Path,
                default=REPOSITORY_ROOT / "script/scene_capability_census_snapshot.json",
            )
            subparser.add_argument(
                "--markdown",
                type=Path,
                default=(
                    REPOSITORY_ROOT
                    / "docs/scene/semantics/scene-corpus-capability-inventory.md"
                ),
            )
        else:
            subparser.add_argument(
                "--snapshot",
                type=Path,
                default=REPOSITORY_ROOT / "script/scene_capability_census_snapshot.json",
            )
            subparser.add_argument(
                "--live",
                action="store_true",
                help="rebuild the private authored corpus instead of querying the committed compact index",
            )
            subparser.add_argument("--family")
            subparser.add_argument("--sample")
            subparser.add_argument("--domain", choices=DOMAINS)
        subparser.set_defaults(handler=handler)
    return parser.parse_args(list(argv) if argv is not None else None)


def main(argv: Iterable[str] | None = None) -> int:
    args = parse_args(argv)
    return args.handler(args)


if __name__ == "__main__":
    raise SystemExit(main())
