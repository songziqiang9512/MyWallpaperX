"""Observe one authored Scene sample and summarize its declaration records."""

from __future__ import annotations
import re
from collections import Counter
from pathlib import Path, PurePosixPath
from typing import Any
from scene_capability_census_effects import (
    census_effect,
    census_image_layer,
    effective_visibility,
    object_kind,
)
from scene_capability_census_io import (
    PkgArchive,
    ResolvedResource,
    SceneResourceView,
    canonical_sha256,
    decode_json,
    normalize_path,
    package_category,
    path_identity,
    sha256_file,
    tree_manifest,
)
from scene_capability_census_particles import census_particle_layer
from scene_capability_census_resources import census_package_resources, shader_profile
from scene_capability_census_profiles import (
    ParameterProfiles,
    SchemaInventory,
    family_key,
    merge_counts,
    occurrence_id,
    recursive_dynamic_features,
    revision_key,
    safe_value_shape,
    scenescript_audio_registrations,
)


AUDIO_SPECTRUM_UNIFORM_PATTERN = re.compile(
    r"^g_AudioSpectrum(16|32|64)(Left|Right)$"
)


AUDIO_RESPONSE_COMBO_KEY = "audioprocessing"


AUDIO_RESPONSE_CONSTANT_KEYS = {
    "frequencymin", "frequencymax", "audioexponent", "audiobounds", "audioamount",
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
    layer_visibilities: list[str],
) -> list[dict[str, Any]]:
    results: list[dict[str, Any]] = []

    def visit(
        value: Any,
        path_pattern: list[str],
        json_pointer: list[str],
        layer_id: Any = None,
        inherited_visibility: str = "unknown",
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
                dynamic_id = occurrence_id("dynamic-input", location)
                results.append({
                    "occurrence_id": dynamic_id,
                    "family_key": family_key("dynamic-input", "+".join(sorted(source_kinds)), shape),
                    "revision_key": canonical_sha256(value),
                    "domain": "dynamic-input",
                    "kind": "+".join(sorted(source_kinds)),
                    "location": location,
                    "effective_visibility": "unknown",
                    "shape": shape,
                    "runtime_proof": {"state": "not-joined"},
                })
                script = value.get("script")
                registration = (
                    scenescript_audio_registrations(script)
                    if isinstance(script, str) else None
                )
                if registration is not None:
                    audio_location = {
                        "sample_id": sample_id,
                        "layer_id": layer_id,
                        "owner_occurrence": dynamic_id,
                        "declaration_kind": "scenescript-registration",
                    }
                    audio_shape = {
                        "owner_domain": "dynamic-input",
                        "resolution_states": registration["resolution_states"],
                        "scope_states": registration["scope_states"],
                        "admission_states": registration["admission_states"],
                    }
                    if registration["cursor_audio_consumer_state"] != "no-cursor-event":
                        audio_shape.update({
                            "cursor_event_exports":
                                registration["cursor_event_exports"],
                            "cursor_event_unresolved_exports":
                                registration["cursor_event_unresolved_exports"],
                            "cursor_audio_consumer_state":
                                registration["cursor_audio_consumer_state"],
                        })
                    results.append({
                        "occurrence_id": occurrence_id(
                            "audio-declaration", audio_location
                        ),
                        "family_key": family_key(
                            "audio-declaration", "scenescript-registration", audio_shape
                        ),
                        "revision_key": revision_key(
                            dynamic_id, registration["call_count"],
                            registration["resolution_states"],
                        ),
                        "domain": "audio-declaration",
                        "kind": "scenescript-registration",
                        "location": audio_location,
                        "effective_visibility": inherited_visibility,
                        "owner_occurrence": dynamic_id,
                        "trigger": (
                            "proven-module-evaluation"
                            if registration["scope_states"] == ["proven-global"]
                            else "mixed-or-unproven"
                        ),
                        **registration,
                    })
            for key, child in sorted(value.items(), key=lambda item: str(item[0]).casefold()):
                visit(
                    child,
                    [*path_pattern, str(key)],
                    [*json_pointer, str(key)],
                    layer_id,
                    inherited_visibility,
                )
        elif isinstance(value, list):
            for index, child in enumerate(value):
                visit(
                    child,
                    [*path_pattern, "[]"],
                    [*json_pointer, str(index)],
                    layer_id,
                    inherited_visibility,
                )

    for object_index, value in enumerate(objects):
        if isinstance(value, dict):
            visit(
                value,
                ["objects", "[]"],
                ["objects", str(object_index)],
                value.get("id"),
                layer_visibilities[object_index],
            )
    general = root.get("general")
    if isinstance(general, dict):
        visit(general, ["general"], ["general"], inherited_visibility="not-applicable")
    return results


def _project_audio_support_occurrences(
    *, sample_id: str, project: dict[str, Any]
) -> list[dict[str, Any]]:
    general = project.get("general")
    if not isinstance(general, dict) or "supportsaudioprocessing" not in general:
        return []
    value = general["supportsaudioprocessing"]
    if value is False:
        return []
    kind = "project-support-enabled" if value is True else "project-support-invalid"
    location = {
        "sample_id": sample_id,
        "declaration_kind": kind,
        "json_pointer": "/general/supportsaudioprocessing",
    }
    shape = {"value_state": "enabled" if value is True else "invalid"}
    return [{
        "occurrence_id": occurrence_id("audio-declaration", location),
        "family_key": family_key("audio-declaration", kind, shape),
        "revision_key": revision_key(value),
        "domain": "audio-declaration",
        "kind": kind,
        "location": location,
        "effective_visibility": "not-applicable",
        "trigger": "editor-capability-hint",
        "value_state": shape["value_state"],
    }]


def _shader_audio_contract(
    view: SceneResourceView, shader_identity: Any
) -> dict[str, Any] | None:
    if not isinstance(shader_identity, str) or not shader_identity:
        return None
    normalized = normalize_path(shader_identity)
    suffix = PurePosixPath(normalized).suffix.casefold()
    stage_suffixes = {".vert", ".frag", ".comp", ".inc"}
    candidates = [normalized] if suffix in stage_suffixes else []
    shader_root = (
        normalized if normalized.casefold().startswith("shaders/")
        else f"shaders/{normalized}"
    )
    if suffix not in stage_suffixes:
        candidates.extend(f"{shader_root}{stage}" for stage in (".vert", ".frag", ".comp"))
    resolutions: set[int] = set()
    channels: set[str] = set()
    stages: set[str] = set()
    exact_resolutions: set[int] = set()
    exact_channels: set[str] = set()
    exact_stages: set[str] = set()
    source_abi_states: Counter[str] = Counter()
    declares_audio_processing_combo = False
    resources: set[tuple[str, str]] = set()
    for candidate in candidates:
        resource = view.resolve(candidate)
        if resource is None:
            continue
        resource_key = (resource.origin, normalize_path(resource.relative_path).casefold())
        if resource_key in resources:
            continue
        resources.add(resource_key)
        profile = shader_profile(resource)
        declares_audio_processing_combo = declares_audio_processing_combo or any(
            str(name).casefold() == AUDIO_RESPONSE_COMBO_KEY
            for name in profile.get("combo_names", [])
        )
        for uniform in profile.get("audio_uniforms", []):
            match = AUDIO_SPECTRUM_UNIFORM_PATTERN.fullmatch(
                str(uniform.get("name", ""))
            )
            if match is None:
                continue
            resolution = int(match.group(1))
            channel = match.group(2).casefold()
            stage = PurePosixPath(resource.relative_path).suffix.casefold().lstrip(".")
            resolutions.add(resolution)
            channels.add(channel)
            stages.add(stage)
            if uniform.get("conditional_state") != "unconditional":
                state = "preprocessor-conditioned"
            elif stage not in {"vert", "frag", "comp"}:
                state = "stage-unresolved"
            elif uniform.get("type") != "float":
                state = "wrong-type"
            elif uniform.get("array_state") == "scalar":
                state = "missing-array"
            elif uniform.get("array_state") != "literal":
                state = "dynamic-array"
            elif uniform.get("array_length") != resolution:
                state = "wrong-array-length"
            else:
                state = "source-shape-exact"
                exact_resolutions.add(resolution)
                exact_channels.add(channel)
                exact_stages.add(stage)
            source_abi_states[state] += 1
    if not resolutions:
        return None
    return {
        "resolutions": sorted(resolutions),
        "channels": sorted(channels),
        "shader_stages": sorted(stages),
        "source_exact_resolutions": sorted(exact_resolutions),
        "source_exact_channels": sorted(exact_channels),
        "source_exact_stages": sorted(exact_stages),
        "source_abi_state_counts": dict(sorted(source_abi_states.items())),
        "runtime_admission_state": "launch-envelope-unjoined",
        "source_declares_audio_processing_combo": declares_audio_processing_combo,
    }


def _audio_owner_occurrences(
    *, sample_id: str, occurrences: list[dict[str, Any]], view: SceneResourceView
) -> list[dict[str, Any]]:
    results: list[dict[str, Any]] = []
    for owner in occurrences:
        owner_domain = owner.get("domain")
        owner_id = owner.get("occurrence_id")
        if not isinstance(owner_id, str):
            continue
        declarations: list[tuple[str, dict[str, Any], str]] = []
        if owner_domain == "material":
            audio_processing_state = str(
                owner.get("audio_processing_state", "absent")
            )
            contract = _shader_audio_contract(view, owner.get("shader_identity"))
            if contract is not None:
                activation_state = (
                    "not-authored"
                    if audio_processing_state == "absent" else audio_processing_state
                )
                declarations.append((
                    "material-host-spectrum",
                    {
                        **contract,
                        "activation_state": activation_state,
                    },
                    "raw-shader-declaration",
                ))
            combo_keys = {
                str(key).casefold()
                for key in [
                    *owner.get("combo_keys", []),
                    *owner.get("instance_combo_keys", []),
                ]
            }
            constant_keys = {
                str(key).casefold()
                for key in [
                    *owner.get("constant_keys", []),
                    *owner.get("instance_constant_keys", []),
                ]
            }
            audio_combo = AUDIO_RESPONSE_COMBO_KEY in combo_keys
            audio_constants = sorted(constant_keys & AUDIO_RESPONSE_CONSTANT_KEYS)
            if audio_combo or audio_constants:
                declarations.append((
                    "material-audio-response",
                    {
                        "has_audio_combo": audio_combo,
                        "audio_constant_keys": audio_constants,
                        "activation_state": audio_processing_state,
                    },
                    "authored-combo-or-constant",
                ))
        elif owner_domain == "particle":
            audio_keys = sorted(
                str(key).casefold()
                for key in owner.get("parameter_keys", [])
                if str(key).casefold().startswith("audioprocessing")
            )
            if audio_keys:
                declarations.append((
                    "particle-audio-response",
                    {
                        "audio_parameter_keys": audio_keys,
                        "activation_state": str(
                            owner.get("audio_processing_state", "missing-mode")
                        ),
                    },
                    "bounded-particle-component",
                ))
        for kind, declaration, trigger in declarations:
            location = {
                "sample_id": sample_id,
                "owner_occurrence": owner_id,
                "declaration_kind": kind,
            }
            shape = {"owner_domain": owner_domain, **declaration}
            results.append({
                "occurrence_id": occurrence_id("audio-declaration", location),
                "family_key": family_key("audio-declaration", kind, shape),
                "revision_key": revision_key(owner_id, declaration),
                "domain": "audio-declaration",
                "kind": kind,
                "location": location,
                "effective_visibility": owner.get("effective_visibility", "unknown"),
                "owner_occurrence": owner_id,
                "trigger": trigger,
                **declaration,
            })
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
    file_digests: dict[Path, str] = {}
    tree_sha, file_count, byte_count = tree_manifest(sample, file_digests=file_digests)
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
        "has_manual_screenshot": any(
            path.is_file() and path.suffix.casefold() == ".png" and path.name.startswith("截屏")
            for path in sample.iterdir()
        ),
        "has_user_observation": (sample / "用户观察说明.md").is_file(),
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
        "project_sha256": file_digests.get(project_path) or sha256_file(project_path),
        "package_sha256": (file_digests.get(package_path) or sha256_file(package_path))
            if package_path.is_file() else None,
        "package_byte_count": package_path.stat().st_size if package_path.is_file() else 0,
        "preview_file": project.get("preview") if isinstance(project.get("preview"), str) else None,
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
            layer_visibilities=layer_visibilities,
        )
        property_occurrences = _project_properties(
            sample_id=sample_id,
            project=project,
            profiles=profiles,
        )
        occurrences.extend(dynamic_occurrences)
        occurrences.extend(property_occurrences)
        occurrences.extend(_project_audio_support_occurrences(
            sample_id=sample_id,
            project=project,
        ))
        occurrences.extend(_audio_owner_occurrences(
            sample_id=sample_id,
            occurrences=occurrences,
            view=view,
        ))
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


def summarize_audio_declarations(
    occurrences: list[dict[str, Any]],
) -> dict[str, Any]:
    audio = [
        item for item in occurrences if item.get("domain") == "audio-declaration"
    ]

    def is_static_consumer_intent(item: dict[str, Any]) -> bool:
        kind = item.get("kind")
        state = item.get("activation_state")
        if kind == "material-host-spectrum":
            return bool(item.get("source_exact_resolutions"))
        if kind in {"material-audio-response", "particle-audio-response"}:
            return state in {"enabled", "dynamic"}
        return kind == "scenescript-registration" and (
            int(item.get("statically_admitted_call_count", 0)) > 0
        )

    by_kind: dict[str, Any] = {}
    for kind in sorted({str(item.get("kind")) for item in audio}):
        values = [item for item in audio if item.get("kind") == kind]
        activation_states = Counter(
            str(item["activation_state"])
            for item in values if "activation_state" in item
        )
        resolution_states = Counter(
            "+".join(str(value) for value in item["resolution_states"])
            for item in values if isinstance(item.get("resolution_states"), list)
        )
        scope_states: Counter[str] = Counter()
        admission_states: Counter[str] = Counter()
        source_abi_states: Counter[str] = Counter()
        runtime_admission_states = Counter(
            str(item["runtime_admission_state"])
            for item in values if "runtime_admission_state" in item
        )
        cursor_audio_consumer_states = Counter(
            str(item["cursor_audio_consumer_state"])
            for item in values
            if "cursor_audio_consumer_state" in item
        )
        cursor_event_exports = Counter(
            "+".join(str(value) for value in item["cursor_event_exports"])
            for item in values
            if isinstance(item.get("cursor_event_exports"), list)
                and item["cursor_event_exports"]
        )
        for item in values:
            scope_states.update(item.get("scope_state_counts", {}))
            admission_states.update(item.get("admission_state_counts", {}))
            source_abi_states.update(item.get("source_abi_state_counts", {}))
        by_kind[kind] = {
            "occurrence_count": len(values),
            "sample_count": len({str(item["location"]["sample_id"]) for item in values}),
            "sample_ids": sorted({str(item["location"]["sample_id"]) for item in values}),
            "activation_state_counts": dict(sorted(activation_states.items())),
            "resolution_state_counts": dict(sorted(resolution_states.items())),
            "scope_state_counts": dict(sorted(scope_states.items())),
            "admission_state_counts": dict(sorted(admission_states.items())),
            "source_abi_state_counts": dict(sorted(source_abi_states.items())),
            "runtime_admission_state_counts": dict(sorted(
                runtime_admission_states.items()
            )),
            "cursor_audio_consumer_state_counts": dict(sorted(
                cursor_audio_consumer_states.items()
            )),
            "cursor_event_export_counts": dict(sorted(
                cursor_event_exports.items()
            )),
        }
    support_samples = {
        str(item["location"]["sample_id"])
        for item in audio if item.get("kind") == "project-support-enabled"
    }
    relationship_samples = {
        str(item["location"]["sample_id"])
        for item in audio if item.get("kind") not in {
            "project-support-enabled", "project-support-invalid",
        }
    }
    static_intent_samples = {
        str(item["location"]["sample_id"])
        for item in audio if is_static_consumer_intent(item)
    }
    cursor_audio_intent_samples = {
        str(item["location"]["sample_id"])
        for item in audio
        if item.get("kind") == "scenescript-registration"
            and item.get("cursor_audio_consumer_state") == "statically-admitted"
    }
    return {
        "declaration_occurrence_count": len(audio),
        "declaration_sample_count": len({
            str(item["location"]["sample_id"]) for item in audio
        }),
        "project_support_sample_count": len(support_samples),
        "relationship_sample_count": len(relationship_samples),
        "relationship_sample_ids": sorted(relationship_samples),
        "static_consumer_intent_sample_count": len(static_intent_samples),
        "static_consumer_intent_sample_ids": sorted(static_intent_samples),
        "cursor_audio_intent_sample_count": len(cursor_audio_intent_samples),
        "cursor_audio_intent_sample_ids": sorted(cursor_audio_intent_samples),
        "support_without_relationship": sorted(support_samples - relationship_samples),
        "relationship_without_support": sorted(relationship_samples - support_samples),
        "support_without_static_intent": sorted(support_samples - static_intent_samples),
        "static_intent_without_support": sorted(static_intent_samples - support_samples),
        "runtime_confirmed_sample_count": 0,
        "runtime_confirmed_sample_ids": [],
        "by_kind": by_kind,
    }
