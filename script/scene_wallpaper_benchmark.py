#!/usr/bin/env python3
"""Run isolated, signed-app Scene wallpaper evidence checks."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any

from web_benchmark_capture import (
    AppIdentityError,
    png_flat_border_ratio,
    png_has_non_black_pixel,
    png_motion_metrics,
    require_fresh_output_dir,
    stage_signed_app,
    verify_staged_app,
)


READY_RE = re.compile(
    r"phase=ready .* layers=(?P<layers>\d+) imageLayers=(?P<images>\d+) "
    r"effects=(?P<effects>\d+) surfaces=(?P<surfaces>\d+)"
)
INTERPRETATION_RE = re.compile(
    r"phase=ready .* interpretation=(?P<path>.+)$",
    re.MULTILINE,
)
STOPPED_RE = re.compile(r"phase=stopped surfacesBefore=(?P<before>\d+) surfacesAfter=(?P<after>\d+)")
LIVE_PROPERTY_UPDATE_RE = re.compile(
    r"phase=live-property-update accepted=(?P<accepted>true|false) "
    r"surfacesBefore=(?P<before>\d+) surfacesAfter=(?P<after>\d+) "
    r"windowsBefore=(?P<windows_before>[\d,]*) windowsAfter=(?P<windows_after>[\d,]*) "
    r"keys=(?P<keys>[^\n]*)"
)
LOADED_RE = re.compile(r"^loaded: (?P<loaded>\d+) / (?P<total>\d+)$", re.MULTILINE)
TEXT_LOADED_RE = re.compile(r"^text loaded: (?P<loaded>\d+) / (?P<total>\d+)$", re.MULTILINE)
TEXT_LAYER_OK_RE = re.compile(r'^text layer (?P<id>\d+) .*: OK ', re.MULTILINE)
PARTICLE_LOADED_RE = re.compile(
    r"^particle loaded: (?P<loaded>\d+) / (?P<total>\d+)$",
    re.MULTILINE,
)
PARTICLE_INITIAL_LIVE_RE = re.compile(
    r"^particle initial live: (?P<live>\d+)$",
    re.MULTILINE,
)
PARTICLE_AUTHORED_RE = re.compile(r"^particle authored: (?P<count>\d+)$", re.MULTILINE)
PARTICLE_VISIBLE_RE = re.compile(r"^particle visible: (?P<count>\d+)$", re.MULTILINE)
PARTICLE_SKIPPED_HIDDEN_RE = re.compile(
    r"^particle skipped hidden: (?P<count>\d+)$",
    re.MULTILINE,
)
PARTICLE_LAYER_OK_RE = re.compile(r'^particle layer (?P<id>\d+) .*: OK ', re.MULTILINE)
SOLID_LAYER_COUNT_RE = re.compile(r"^solidLayerCount: (?P<count>\d+)$", re.MULTILINE)
SOLID_LAYER_OK_RE = re.compile(
    r'^layer (?P<id>\d+) .*: OK procedural solid(?:\s|$)',
    re.MULTILINE,
)
UTILITY_LAYER_COUNT_RE = re.compile(r"^utilityLayerCount: (?P<count>\d+)$", re.MULTILINE)
UTILITY_CAPTURE_COUNT_RE = re.compile(
    r"^utilityCapturePlannedCount: (?P<count>\d+)$", re.MULTILINE
)
UTILITY_DEPENDENCY_COUNT_RE = re.compile(
    r"^utilityDependencyEdgeCount: (?P<count>\d+)$", re.MULTILINE
)
UTILITY_NAMED_TARGET_PLANNED_RE = re.compile(
    r"^utilityNamedTargetPlannedCount: (?P<count>\d+)$", re.MULTILINE
)
UTILITY_NAMED_CONSUMER_COUNT_RE = re.compile(
    r"^utilityNamedConsumerCount: (?P<count>\d+)$", re.MULTILINE
)
UTILITY_NAMED_BINDING_PLANNED_RE = re.compile(
    r"^utilityNamedBindingPlannedCount: (?P<count>\d+)$", re.MULTILINE
)
UTILITY_NAMED_TARGET_GAP_RE = re.compile(
    r"^utilityNamedTargetGapCount: (?P<count>\d+)$", re.MULTILINE
)
UTILITY_LAYER_RE = re.compile(
    r"^utility layer (?P<id>\d+): (?P<disposition>\w+) kind=(?P<kind>\w+)",
    re.MULTILINE,
)
UTILITY_CAPTURE_EXECUTION_RE = re.compile(
    r"phase=utility-capture layer=(?P<id>\d+) status=(?P<status>succeeded|failed)"
)
AUTHORED_EFFECT_GRAPH_EXECUTION_RE = re.compile(
    r"phase=authored-effect-graph layer=(?P<id>\d+) status=(?P<status>succeeded|failed)"
)
AUTHORED_EFFECT_GRAPH_LEGACY_BLUR_BLOCKED_RE = re.compile(
    r"^authoredEffectGraphLegacyBlurBlockedLayerIDs: ?(?P<ids>[\d,]*)$",
    re.MULTILINE,
)
AUTHORED_EFFECT_GRAPH_LOCAL_CONTRAST_COUNT_RE = re.compile(
    r"^authoredEffectGraphLocalContrastCount: (?P<count>\d+)$",
    re.MULTILINE,
)
AUTHORED_EFFECT_GRAPH_OPACITY_COUNT_RE = re.compile(
    r"^authoredEffectGraphOpacityCount: (?P<count>\d+)$",
    re.MULTILINE,
)
AUTHORED_EFFECT_GRAPH_OPACITY_LAYER_RE = re.compile(
    r"^(?:(?:image|text|solid) )?layer (?P<id>\d+)\b[^\n]*?"
    r"(?:effect runtime foliagesway-uv; )?"
    r"effect runtime opacity-authored;",
    re.MULTILINE,
)
AUTHORED_EFFECT_GRAPH_WORKSHOP_SHADOW_COUNT_RE = re.compile(
    r"^authoredEffectGraphWorkshopShadowCount: (?P<count>\d+)$",
    re.MULTILINE,
)
AUTHORED_EFFECT_GRAPH_SHAKE_COUNT_RE = re.compile(
    r"^authoredEffectGraphShakeCount: (?P<count>\d+)$",
    re.MULTILINE,
)
AUTHORED_EFFECT_GRAPH_CHAIN_COUNT_RE = re.compile(
    r"^authoredEffectGraphChainCount: (?P<count>\d+)$",
    re.MULTILINE,
)
AUTHORED_EFFECT_GRAPH_STAGE_COUNT_RE = re.compile(
    r"^authoredEffectGraphStageCount: (?P<count>\d+)$",
    re.MULTILINE,
)
NAMED_TARGET_CAPTURE_EXECUTION_RE = re.compile(
    r"phase=named-target-capture layer=(?P<id>\d+) status=(?P<status>succeeded|failed)"
)
NAMED_TARGET_BINDING_EXECUTION_RE = re.compile(
    r"phase=named-target-binding layer=(?P<id>\d+) status=(?P<status>succeeded|failed)"
)
IMAGE_BLEND_PLANNED_RE = re.compile(
    r"^imageBlendPlannedCount: (?P<count>\d+)$", re.MULTILINE
)
IMAGE_BLEND_EXECUTION_RE = re.compile(
    r"phase=image-blend layer=(?P<id>\d+) status=(?P<status>succeeded|failed)"
)
FLOAT_PATTERN = r"[-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?"
CAMERA_RE = re.compile(
    r"^camera: projection=(?P<projection>\S+) parallax=(?P<parallax>true|false) "
    rf"amount=(?P<amount>{FLOAT_PATTERN}) (?:delay=(?P<delay>{FLOAT_PATTERN}) )?"
    rf"mouseInfluence=(?P<influence>{FLOAT_PATTERN})$",
    re.MULTILINE,
)
SAMPLE_ROOT_DERIVED_FILES = (
    ".mywallpaperx-scene-interpretation.json",
    ".mywallpaperx-scene-preview-log.txt",
)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_matrix(path: Path) -> dict[str, Any]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if payload.get("schema_version") != 1 or not isinstance(payload.get("samples"), list):
        raise ValueError(f"invalid Scene matrix: {path}")
    return payload


def scene_package_path(source: Path) -> Path | None:
    project_path = source / "project.json"
    if not project_path.is_file():
        return None
    try:
        project = json.loads(project_path.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError):
        project = {}
    raw_entry = project.get("file")
    entry = raw_entry.strip().replace("\\", "/") if isinstance(raw_entry, str) else ""
    entry_name = Path(entry).name if entry else "scene.json"
    derived_name = str(Path(entry_name).with_suffix(".pkg"))
    package_names = (
        [derived_name]
        if derived_name == "scene.pkg"
        else [derived_name, "scene.pkg"]
    )
    return next((source / name for name in package_names if (source / name).is_file()), None)


def copy_sample(source: Path, destination: Path) -> None:
    if not (source / "project.json").is_file() or scene_package_path(source) is None:
        raise FileNotFoundError(f"Scene sample is incomplete: {source}")
    shutil.copytree(source, destination)


def pass_metadata_metrics(passes: list[Any]) -> tuple[int, int, int]:
    slot_count = 0
    slot_holes = 0
    combo_count = 0
    for item in passes:
        if not isinstance(item, dict):
            raise ValueError("Scene interpretation pass is not an object")
        slots = item.get("textureSlots")
        combos = item.get("combos")
        if not isinstance(slots, list) or any(slot is not None and not isinstance(slot, str) for slot in slots):
            raise ValueError("Scene interpretation textureSlots has an invalid shape")
        if not isinstance(combos, dict) or any(type(value) is not int for value in combos.values()):
            raise ValueError("Scene interpretation combos has an invalid shape")
        slot_count += len(slots)
        slot_holes += sum(slot is None for slot in slots)
        combo_count += len(combos)
    return slot_count, slot_holes, combo_count


def shader_contract_metrics(contracts: Any) -> dict[str, Any]:
    if not isinstance(contracts, list):
        raise ValueError("Scene interpretation shaderContracts has an invalid shape")

    authored_count = 0
    builtin_count = 0
    stage_count = 0
    diagnostic_count = 0
    aggregate_entries: list[list[str]] = []
    identities: set[str] = set()
    for contract in contracts:
        if not isinstance(contract, dict):
            raise ValueError("Scene interpretation shader contract is not an object")
        identity = contract.get("identity")
        source_kind = contract.get("sourceKind")
        stages = contract.get("stages")
        diagnostics = contract.get("diagnostics")
        canonical_sha256 = contract.get("canonicalSHA256")
        if not isinstance(identity, str) or not identity:
            raise ValueError("Scene interpretation shader contract identity has an invalid shape")
        if identity in identities:
            raise ValueError("Scene interpretation shader contract identity is duplicated")
        identities.add(identity)
        if source_kind not in {"authoredSource", "hostBuiltin"}:
            raise ValueError("Scene interpretation shader contract sourceKind has an invalid shape")
        if not isinstance(stages, list):
            raise ValueError("Scene interpretation shader contract stages has an invalid shape")
        if not isinstance(diagnostics, list):
            raise ValueError("Scene interpretation shader contract diagnostics has an invalid shape")
        if not isinstance(canonical_sha256, str) or re.fullmatch(
            r"[0-9a-f]{64}", canonical_sha256
        ) is None:
            raise ValueError(
                "Scene interpretation shader contract canonicalSHA256 has an invalid shape"
            )

        stage_kinds: set[str] = set()
        for stage in stages:
            if not isinstance(stage, dict):
                raise ValueError("Scene interpretation shader contract stage is not an object")
            kind = stage.get("kind")
            relative_path = stage.get("relativePath")
            source = stage.get("source")
            raw_sha256 = stage.get("rawSHA256")
            if kind not in {"vertex", "fragment"} or kind in stage_kinds:
                raise ValueError("Scene interpretation shader contract stage kind is invalid")
            stage_kinds.add(kind)
            if relative_path != f"shaders/{identity}.{'vert' if kind == 'vertex' else 'frag'}":
                raise ValueError("Scene interpretation shader contract stage path is invalid")
            if not isinstance(source, str) or not isinstance(raw_sha256, str):
                raise ValueError("Scene interpretation shader contract stage source is invalid")
            if raw_sha256 != hashlib.sha256(source.encode("utf-8")).hexdigest():
                raise ValueError("Scene interpretation shader contract stage rawSHA256 mismatch")

            for field in ("includes", "annotations", "declarations"):
                if not isinstance(stage.get(field), list):
                    raise ValueError(
                        f"Scene interpretation shader contract stage {field} is invalid"
                    )
            for include in stage["includes"]:
                if not isinstance(include, dict) or not isinstance(include.get("relativePath"), str):
                    raise ValueError("Scene interpretation shader contract include is invalid")
                if not isinstance(include.get("raw"), str) or type(include.get("line")) is not int:
                    raise ValueError("Scene interpretation shader contract include is invalid")
            for annotation in stage["annotations"]:
                marker = annotation.get("marker") if isinstance(annotation, dict) else None
                if not isinstance(annotation, dict) or "value" not in annotation:
                    raise ValueError("Scene interpretation shader contract annotation is invalid")
                if marker is not None and not isinstance(marker, str):
                    raise ValueError("Scene interpretation shader contract annotation is invalid")
                if not isinstance(annotation.get("raw"), str) or type(annotation.get("line")) is not int:
                    raise ValueError("Scene interpretation shader contract annotation is invalid")
            for declaration in stage["declarations"]:
                if not isinstance(declaration, dict) or declaration.get("kind") not in {
                    "uniform", "attribute", "varying"
                }:
                    raise ValueError("Scene interpretation shader contract declaration is invalid")
                if not all(isinstance(declaration.get(field), str) for field in ("type", "name", "raw")):
                    raise ValueError("Scene interpretation shader contract declaration is invalid")
                if type(declaration.get("line")) is not int:
                    raise ValueError("Scene interpretation shader contract declaration is invalid")
                if declaration.get("arraySuffix") is not None and not isinstance(
                    declaration.get("arraySuffix"), str
                ):
                    raise ValueError("Scene interpretation shader contract declaration is invalid")
                if declaration.get("arraySize") is not None and type(
                    declaration.get("arraySize")
                ) is not int:
                    raise ValueError("Scene interpretation shader contract declaration is invalid")

        diagnostic_codes = {
            "duplicateIdentity", "invalidReference", "pathEscape", "symlinkEscape",
            "missingVertexStage", "missingFragmentStage", "unreadableSource", "invalidUTF8",
            "malformedAnnotation",
        }
        for diagnostic in diagnostics:
            if not isinstance(diagnostic, dict) or diagnostic.get("code") not in diagnostic_codes:
                raise ValueError("Scene interpretation shader contract diagnostic is invalid")
            if not isinstance(diagnostic.get("message"), str):
                raise ValueError("Scene interpretation shader contract diagnostic is invalid")
            if diagnostic.get("relativePath") is not None and not isinstance(
                diagnostic.get("relativePath"), str
            ):
                raise ValueError("Scene interpretation shader contract diagnostic is invalid")
            if diagnostic.get("line") is not None and type(diagnostic.get("line")) is not int:
                raise ValueError("Scene interpretation shader contract diagnostic is invalid")
        if source_kind == "hostBuiltin" and (stages or diagnostics):
            raise ValueError("Scene interpretation host builtin shader contract is invalid")

        authored_count += source_kind == "authoredSource"
        builtin_count += source_kind == "hostBuiltin"
        stage_count += len(stages)
        diagnostic_count += len(diagnostics)
        aggregate_entries.append([identity, canonical_sha256])

    # UTF-8 JSON over sorted [identity, canonicalSHA256] pairs is the stable wire encoding.
    aggregate_sha256 = hashlib.sha256(json.dumps(
        sorted(aggregate_entries),
        ensure_ascii=True,
        separators=(",", ":"),
    ).encode("utf-8")).hexdigest()
    return {
        "shader_contract_count": len(contracts),
        "shader_contract_authored_count": authored_count,
        "shader_contract_builtin_count": builtin_count,
        "shader_contract_stage_count": stage_count,
        "shader_contract_diagnostic_count": diagnostic_count,
        "shader_contract_aggregate_sha256": aggregate_sha256,
    }


def layer_graph_metrics(layers: list[dict[str, Any]]) -> dict[str, Any]:
    layers_by_id = {layer["id"]: layer for layer in layers if type(layer.get("id")) is int}

    def is_effectively_visible(layer: dict[str, Any]) -> bool:
        current: dict[str, Any] | None = layer
        visited: set[int] = set()
        while current is not None:
            layer_id = current.get("id")
            if current.get("visible") is False or layer_id in visited:
                return False
            if type(layer_id) is int:
                visited.add(layer_id)
            parent_id = current.get("parentID")
            current = layers_by_id.get(parent_id) if type(parent_id) is int else None
        return True

    def hierarchy_depth(layer: dict[str, Any]) -> int:
        depth = 0
        current = layer
        visited: set[int] = set()
        while type(current.get("parentID")) is int:
            layer_id = current.get("id")
            if layer_id in visited:
                break
            if type(layer_id) is int:
                visited.add(layer_id)
            parent = layers_by_id.get(current["parentID"])
            if parent is None:
                break
            depth += 1
            current = parent
        return depth

    effective_visible_ids = [
        layer["id"]
        for layer in layers
        if type(layer.get("id")) is int and is_effectively_visible(layer)
    ]
    parent_ids = {
        layer["parentID"]
        for layer in layers
        if type(layer.get("parentID")) is int
    }
    return {
        "root_layer_count": sum(layer.get("parentID") is None for layer in layers),
        "child_edge_count": sum(type(layer.get("parentID")) is int for layer in layers),
        "parent_layer_count": len(parent_ids),
        "max_hierarchy_depth": max((hierarchy_depth(layer) for layer in layers), default=0),
        "effective_visible_layer_count": len(effective_visible_ids),
        "effective_visible_layer_ids": effective_visible_ids,
    }


def interpretation_metrics(path: Path) -> dict[str, Any]:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
        shader_contracts = shader_contract_metrics(payload["shaderContracts"])
        descriptor = payload["renderDescriptor"]
        layers = descriptor.get("layers", [])
        effect_passes = [
            item
            for layer in descriptor.get("layers", [])
            for effect in layer.get("effects", [])
            for item in effect.get("passes", [])
        ]
        material_passes = descriptor.get("materialPasses", [])
        effect_definitions = descriptor.get("effectDefinitions", [])
        definition_passes = [
            item
            for definition in effect_definitions
            for item in definition.get("passes", [])
        ]
        definition_framebuffers = [
            item
            for definition in effect_definitions
            for item in definition.get("framebuffers", [])
        ]
        definition_diagnostics = descriptor.get("effectDefinitionDiagnostics", [])
        effect_graphs = payload.get("authoredEffectRenderPlans", [])
        effect_graph_nodes = [
            node
            for graph_plan in effect_graphs
            for node in graph_plan.get("nodes", [])
        ]
        effect_graph_blockers = [
            blocker
            for graph_plan in effect_graphs
            for blocker in graph_plan.get("blockers", [])
        ]
        effect_graph_blocker_reasons: dict[str, int] = {}
        for blocker in effect_graph_blockers:
            reason = blocker.get("reason")
            if isinstance(reason, str):
                effect_graph_blocker_reasons[reason] = (
                    effect_graph_blocker_reasons.get(reason, 0) + 1
                )
        effect_graph_sha256 = hashlib.sha256(json.dumps(
            effect_graphs,
            ensure_ascii=True,
            sort_keys=True,
            separators=(",", ":"),
        ).encode("utf-8")).hexdigest()
        graph = layer_graph_metrics(layers)
        solid_layers = [layer for layer in layers if layer.get("contentKind") == "solid"]
        utility_layers = [
            layer
            for layer in layers
            if layer.get("contentKind") in {"composition", "project", "fullscreen"}
        ]
        dependency_edges = [
            (layer.get("id"), dependency_id)
            for layer in layers
            for dependency_id in layer.get("dependencyLayerIDs", [])
            if type(layer.get("id")) is int and type(dependency_id) is int
        ]
        solid_layer_ids = [
            layer["id"] for layer in solid_layers if type(layer.get("id")) is int
        ]
        effective_visible_ids = set(graph["effective_visible_layer_ids"])
        stock_opacity_single_effect_candidate_layer_ids = sorted({
            graph_plan["layerID"]
            for graph_plan in effect_graphs
            if type(graph_plan.get("layerID")) is int
            and graph_plan["layerID"] in effective_visible_ids
            and len(graph_plan.get("effects", [])) == 1
            and str(graph_plan["effects"][0].get("definitionPath", ""))
                .replace("\\", "/").lower() == "effects/opacity/effect.json"
        })
        effective_visible_solid_layer_ids = [
            layer_id for layer_id in solid_layer_ids if layer_id in effective_visible_ids
        ]
        authored_solid_color_layer_ids = [
            layer["id"]
            for layer in solid_layers
            if type(layer.get("id")) is int and isinstance(layer.get("colorRGB"), list)
        ]
        parallax_layers = [
            layer
            for layer in layers
            if isinstance(layer.get("parallaxDepthXY"), list)
            and any(abs(float(value)) > 1e-8 for value in layer["parallaxDepthXY"])
        ]
        effect_slot_count, effect_slot_holes, effect_combo_count = pass_metadata_metrics(effect_passes)
        material_slot_count, material_slot_holes, material_combo_count = pass_metadata_metrics(material_passes)
        return {
            "format_version": int(payload["formatVersion"]),
            **shader_contracts,
            "effect_texture_slot_count": effect_slot_count,
            "effect_texture_slot_hole_count": effect_slot_holes,
            "effect_combo_entry_count": effect_combo_count,
            "material_texture_slot_count": material_slot_count,
            "material_texture_slot_hole_count": material_slot_holes,
            "material_combo_entry_count": material_combo_count,
            "effect_definition_count": len(effect_definitions),
            "effect_definition_pass_count": len(definition_passes),
            "effect_definition_material_pass_count": sum(
                isinstance(item.get("materialPath"), str) for item in definition_passes
            ),
            "effect_definition_fbo_count": len(definition_framebuffers),
            "effect_definition_copy_command_count": sum(
                item.get("command") == "copy" for item in definition_passes
            ),
            "effect_definition_swap_command_count": sum(
                item.get("command") == "swap" for item in definition_passes
            ),
            "effect_definition_diagnostic_count": len(definition_diagnostics),
            "effect_graph_layer_count": len(effect_graphs),
            "effect_graph_effect_count": sum(
                len(graph_plan.get("effects", [])) for graph_plan in effect_graphs
            ),
            "effect_graph_node_count": len(effect_graph_nodes),
            "effect_graph_material_node_count": sum(
                node.get("kind") == "material" for node in effect_graph_nodes
            ),
            "effect_graph_copy_node_count": sum(
                node.get("kind") == "copy" for node in effect_graph_nodes
            ),
            "effect_graph_swap_node_count": sum(
                node.get("kind") == "swap" for node in effect_graph_nodes
            ),
            "effect_graph_render_target_count": sum(
                len(graph_plan.get("renderTargets", [])) for graph_plan in effect_graphs
            ),
            "effect_graph_blocker_count": len(effect_graph_blockers),
            "effect_graph_blocker_reasons": effect_graph_blocker_reasons,
            "effect_graph_unblocked_layer_count": sum(
                not graph_plan.get("blockers", []) for graph_plan in effect_graphs
            ),
            "effect_graph_sha256": effect_graph_sha256,
            "stock_opacity_single_effect_candidate_layer_ids":
                stock_opacity_single_effect_candidate_layer_ids,
            "visible_layer_count": sum(layer.get("visible") is not False for layer in layers),
            "visible_layer_ids": [layer.get("id") for layer in layers if layer.get("visible") is not False],
            **graph,
            "solid_layer_count": len(solid_layers),
            "solid_layer_ids": solid_layer_ids,
            "authored_solid_color_layer_count": len(authored_solid_color_layer_ids),
            "authored_solid_color_layer_ids": authored_solid_color_layer_ids,
            "effective_visible_solid_layer_count": len(effective_visible_solid_layer_ids),
            "effective_visible_solid_layer_ids": effective_visible_solid_layer_ids,
            "composition_layer_count": sum(
                layer.get("contentKind") == "composition" for layer in utility_layers
            ),
            "project_layer_count": sum(
                layer.get("contentKind") == "project" for layer in utility_layers
            ),
            "fullscreen_layer_count": sum(
                layer.get("contentKind") == "fullscreen" for layer in utility_layers
            ),
            "utility_layer_ids": [layer["id"] for layer in utility_layers],
            "dependency_edge_count": len(dependency_edges),
            "dependency_consumer_layer_ids": sorted({edge[0] for edge in dependency_edges}),
            "dependency_source_layer_ids": sorted({edge[1] for edge in dependency_edges}),
            "authored_parallax_layer_count": len(parallax_layers),
            "authored_parallax_layer_ids": [layer.get("id") for layer in parallax_layers],
            "parallax_propagation_block_count": sum(
                layer.get("disablesParallaxPropagation") is True for layer in layers
            ),
            "text_values": [layer.get("text") for layer in layers if isinstance(layer.get("text"), str)],
            "effect_files": sorted({
                effect.get("file")
                for layer in layers
                for effect in layer.get("effects", [])
                if isinstance(effect.get("file"), str)
            }),
            "built_in_reference_count": int(descriptor.get("builtInReferenceCount", 0)),
            "missing_resource_count": len(descriptor.get("missingResources", [])),
            "error": None,
        }
    except (AttributeError, KeyError, TypeError, ValueError, json.JSONDecodeError, OSError) as error:
        return {
            "format_version": None,
            "shader_contract_count": 0,
            "shader_contract_authored_count": 0,
            "shader_contract_builtin_count": 0,
            "shader_contract_stage_count": 0,
            "shader_contract_diagnostic_count": 0,
            "shader_contract_aggregate_sha256": None,
            "effect_texture_slot_count": 0,
            "effect_texture_slot_hole_count": 0,
            "effect_combo_entry_count": 0,
            "material_texture_slot_count": 0,
            "material_texture_slot_hole_count": 0,
            "material_combo_entry_count": 0,
            "effect_definition_count": 0,
            "effect_definition_pass_count": 0,
            "effect_definition_material_pass_count": 0,
            "effect_definition_fbo_count": 0,
            "effect_definition_copy_command_count": 0,
            "effect_definition_swap_command_count": 0,
            "effect_definition_diagnostic_count": 0,
            "effect_graph_layer_count": 0,
            "effect_graph_effect_count": 0,
            "effect_graph_node_count": 0,
            "effect_graph_material_node_count": 0,
            "effect_graph_copy_node_count": 0,
            "effect_graph_swap_node_count": 0,
            "effect_graph_render_target_count": 0,
            "effect_graph_blocker_count": 0,
            "effect_graph_blocker_reasons": {},
            "effect_graph_unblocked_layer_count": 0,
            "effect_graph_sha256": None,
            "stock_opacity_single_effect_candidate_layer_ids": [],
            "visible_layer_count": 0,
            "visible_layer_ids": [],
            "root_layer_count": 0,
            "child_edge_count": 0,
            "parent_layer_count": 0,
            "max_hierarchy_depth": 0,
            "effective_visible_layer_count": 0,
            "effective_visible_layer_ids": [],
            "solid_layer_count": 0,
            "solid_layer_ids": [],
            "authored_solid_color_layer_count": 0,
            "authored_solid_color_layer_ids": [],
            "effective_visible_solid_layer_count": 0,
            "effective_visible_solid_layer_ids": [],
            "composition_layer_count": 0,
            "project_layer_count": 0,
            "fullscreen_layer_count": 0,
            "utility_layer_ids": [],
            "dependency_edge_count": 0,
            "dependency_consumer_layer_ids": [],
            "dependency_source_layer_ids": [],
            "authored_parallax_layer_count": 0,
            "authored_parallax_layer_ids": [],
            "parallax_propagation_block_count": 0,
            "text_values": [],
            "effect_files": [],
            "built_in_reference_count": 0,
            "missing_resource_count": 0,
            "error": str(error),
        }


def particle_runtime_metrics(preview_text: str) -> dict[str, Any]:
    loaded_match = PARTICLE_LOADED_RE.search(preview_text)
    initial_live_match = PARTICLE_INITIAL_LIVE_RE.search(preview_text)
    authored_match = PARTICLE_AUTHORED_RE.search(preview_text)
    visible_match = PARTICLE_VISIBLE_RE.search(preview_text)
    skipped_hidden_match = PARTICLE_SKIPPED_HIDDEN_RE.search(preview_text)
    loaded = int(loaded_match.group("loaded")) if loaded_match else 0
    candidates = int(loaded_match.group("total")) if loaded_match else 0
    return {
        "has_load_evidence": loaded_match is not None,
        "has_initial_live_evidence": initial_live_match is not None,
        "has_visibility_evidence": all(
            match is not None
            for match in (authored_match, visible_match, skipped_hidden_match)
        ),
        "loaded": loaded,
        "candidates": candidates,
        "loaded_ratio": loaded / candidates if candidates else 0.0,
        "initial_live": int(initial_live_match.group("live")) if initial_live_match else 0,
        "authored": int(authored_match.group("count")) if authored_match else 0,
        "visible": int(visible_match.group("count")) if visible_match else 0,
        "skipped_hidden": int(skipped_hidden_match.group("count")) if skipped_hidden_match else 0,
        "loaded_layer_ids": [int(match.group("id")) for match in PARTICLE_LAYER_OK_RE.finditer(preview_text)],
    }


def solid_runtime_metrics(preview_text: str) -> dict[str, Any]:
    count_match = SOLID_LAYER_COUNT_RE.search(preview_text)
    loaded_layer_ids = [
        int(match.group("id")) for match in SOLID_LAYER_OK_RE.finditer(preview_text)
    ]
    candidates = int(count_match.group("count")) if count_match else 0
    return {
        "has_count_evidence": count_match is not None,
        "loaded": len(loaded_layer_ids),
        "candidates": candidates,
        "loaded_ratio": len(loaded_layer_ids) / candidates if candidates else 0.0,
        "loaded_layer_ids": loaded_layer_ids,
    }


def utility_runtime_metrics(preview_text: str) -> dict[str, Any]:
    count_match = UTILITY_LAYER_COUNT_RE.search(preview_text)
    capture_match = UTILITY_CAPTURE_COUNT_RE.search(preview_text)
    dependency_match = UTILITY_DEPENDENCY_COUNT_RE.search(preview_text)
    named_consumer_match = UTILITY_NAMED_CONSUMER_COUNT_RE.search(preview_text)
    named_target_match = UTILITY_NAMED_TARGET_PLANNED_RE.search(preview_text)
    named_binding_match = UTILITY_NAMED_BINDING_PLANNED_RE.search(preview_text)
    named_gap_match = UTILITY_NAMED_TARGET_GAP_RE.search(preview_text)
    layers = [
        {
            "id": int(match.group("id")),
            "disposition": match.group("disposition"),
            "kind": match.group("kind"),
        }
        for match in UTILITY_LAYER_RE.finditer(preview_text)
    ]
    return {
        "has_evidence": all(
            match is not None
            for match in (
                count_match,
                capture_match,
                dependency_match,
                named_consumer_match,
                named_target_match,
                named_binding_match,
                named_gap_match,
            )
        ),
        "candidates": int(count_match.group("count")) if count_match else 0,
        "capture_planned": int(capture_match.group("count")) if capture_match else 0,
        "dependency_edges": int(dependency_match.group("count")) if dependency_match else 0,
        "named_consumers": int(named_consumer_match.group("count")) if named_consumer_match else 0,
        "named_target_planned": int(named_target_match.group("count")) if named_target_match else 0,
        "named_binding_planned": int(named_binding_match.group("count")) if named_binding_match else 0,
        "named_target_gaps": int(named_gap_match.group("count")) if named_gap_match else 0,
        "layers": layers,
    }


def utility_runtime_failures(
    sample: dict[str, Any],
    metrics: dict[str, Any],
) -> list[str]:
    expected_metrics = {
        "expected_utility_candidates": "candidates",
        "expected_utility_capture_planned": "capture_planned",
        "expected_utility_dependency_edges": "dependency_edges",
        "expected_utility_named_consumers": "named_consumers",
        "expected_utility_named_target_planned": "named_target_planned",
        "expected_utility_named_binding_planned": "named_binding_planned",
        "expected_utility_named_target_gaps": "named_target_gaps",
    }
    requires_evidence = any(key in sample for key in expected_metrics) or bool(
        sample.get("required_utility_dispositions")
    )
    if requires_evidence and not metrics["has_evidence"]:
        return ["utility layer runtime evidence missing"]

    failures: list[str] = []
    for expectation, metric in expected_metrics.items():
        if expectation in sample and metrics[metric] != int(sample[expectation]):
            failures.append(f"utility {metric} mismatch")
    actual_dispositions = {
        str(layer["id"]): layer["disposition"] for layer in metrics["layers"]
    }
    for layer_id, disposition in sample.get("required_utility_dispositions", {}).items():
        if actual_dispositions.get(str(layer_id)) != disposition:
            failures.append(
                f"utility layer {layer_id} disposition should be {disposition}"
            )
    return failures


def utility_capture_execution_metrics(log_text: str) -> dict[str, Any]:
    return capture_execution_metrics(log_text, UTILITY_CAPTURE_EXECUTION_RE)


def authored_effect_graph_execution_metrics(log_text: str) -> dict[str, Any]:
    return capture_execution_metrics(log_text, AUTHORED_EFFECT_GRAPH_EXECUTION_RE)


def authored_effect_graph_legacy_blur_blocked_layer_ids(preview_text: str) -> list[int]:
    match = AUTHORED_EFFECT_GRAPH_LEGACY_BLUR_BLOCKED_RE.search(preview_text)
    if match is None or not match.group("ids"):
        return []
    return sorted({int(value) for value in match.group("ids").split(",")})


def authored_effect_graph_local_contrast_count(preview_text: str) -> int | None:
    match = AUTHORED_EFFECT_GRAPH_LOCAL_CONTRAST_COUNT_RE.search(preview_text)
    return int(match.group("count")) if match is not None else None


def authored_effect_graph_opacity_count(preview_text: str) -> int | None:
    match = AUTHORED_EFFECT_GRAPH_OPACITY_COUNT_RE.search(preview_text)
    return int(match.group("count")) if match is not None else None


def authored_effect_graph_opacity_layer_ids(preview_text: str) -> list[int]:
    return sorted({
        int(match.group("id"))
        for match in AUTHORED_EFFECT_GRAPH_OPACITY_LAYER_RE.finditer(preview_text)
    })


def authored_effect_graph_workshop_shadow_count(preview_text: str) -> int | None:
    match = AUTHORED_EFFECT_GRAPH_WORKSHOP_SHADOW_COUNT_RE.search(preview_text)
    return int(match.group("count")) if match is not None else None


def authored_effect_graph_shake_count(preview_text: str) -> int | None:
    match = AUTHORED_EFFECT_GRAPH_SHAKE_COUNT_RE.search(preview_text)
    return int(match.group("count")) if match is not None else None


def authored_effect_graph_chain_metrics(preview_text: str) -> dict[str, int | None]:
    chain_match = AUTHORED_EFFECT_GRAPH_CHAIN_COUNT_RE.search(preview_text)
    stage_match = AUTHORED_EFFECT_GRAPH_STAGE_COUNT_RE.search(preview_text)
    return {
        "chain_count": int(chain_match.group("count")) if chain_match else None,
        "stage_count": int(stage_match.group("count")) if stage_match else None,
    }


def named_target_capture_execution_metrics(log_text: str) -> dict[str, Any]:
    return capture_execution_metrics(log_text, NAMED_TARGET_CAPTURE_EXECUTION_RE)


def named_target_binding_execution_metrics(log_text: str) -> dict[str, Any]:
    return capture_execution_metrics(log_text, NAMED_TARGET_BINDING_EXECUTION_RE)


def image_blend_runtime_metrics(
    preview_text: str,
    log_text: str,
) -> dict[str, Any]:
    planned_match = IMAGE_BLEND_PLANNED_RE.search(preview_text)
    execution = capture_execution_metrics(log_text, IMAGE_BLEND_EXECUTION_RE)
    return {
        "has_evidence": planned_match is not None,
        "planned": int(planned_match.group("count")) if planned_match else 0,
        **execution,
    }


def image_blend_runtime_failures(
    sample: dict[str, Any],
    metrics: dict[str, Any],
) -> list[str]:
    requires_evidence = "expected_image_blend_planned" in sample or bool(
        sample.get("required_image_blend_succeeded_layer_ids")
    )
    if requires_evidence and not metrics["has_evidence"]:
        return ["image blend runtime evidence missing"]
    failures: list[str] = []
    if "expected_image_blend_planned" in sample:
        if metrics["planned"] != int(sample["expected_image_blend_planned"]):
            failures.append("image blend planned count mismatch")
    succeeded = set(metrics["succeeded_layer_ids"])
    if len(succeeded) < metrics["planned"]:
        failures.append("image blend execution below planned count")
    for layer_id in sample.get("required_image_blend_succeeded_layer_ids", []):
        if layer_id not in succeeded:
            failures.append(f"image blend consumer {layer_id} should succeed")
    return failures


def capture_execution_metrics(
    log_text: str,
    pattern: re.Pattern[str],
) -> dict[str, Any]:
    succeeded: set[int] = set()
    failed: set[int] = set()
    for match in pattern.finditer(log_text):
        layer_id = int(match.group("id"))
        if match.group("status") == "succeeded":
            succeeded.add(layer_id)
            failed.discard(layer_id)
        elif layer_id not in succeeded:
            failed.add(layer_id)
    return {
        "succeeded_layer_ids": sorted(succeeded),
        "failed_layer_ids": sorted(failed),
    }


def authored_effect_graph_failures(
    sample: dict[str, Any],
    metrics: dict[str, Any],
    legacy_blur_blocked_layer_ids: list[int],
    local_contrast_count: int | None,
    chain_metrics: dict[str, int | None] | None = None,
    workshop_shadow_count: int | None = None,
    shake_count: int | None = None,
    opacity_count: int | None = None,
    route_only_effect_count: int | None = None,
    opacity_layer_ids: list[int] | None = None,
) -> list[str]:
    failures = [
        f"authored effect graph layer {layer_id} failed"
        for layer_id in metrics["failed_layer_ids"]
    ]
    succeeded = set(metrics["succeeded_layer_ids"])
    expected = sample.get("expected_authored_effect_graph_succeeded_layer_ids")
    if expected is not None and succeeded != set(expected):
        failures.append("authored effect graph succeeded layer IDs mismatch")
    for layer_id in sample.get("required_authored_effect_graph_succeeded_layer_ids", []):
        if layer_id not in succeeded:
            failures.append(f"authored effect graph layer {layer_id} should succeed")
    expected_blocked = sample.get(
        "expected_authored_effect_graph_legacy_blur_blocked_layer_ids"
    )
    if expected_blocked is not None:
        if set(legacy_blur_blocked_layer_ids) != set(expected_blocked):
            failures.append("authored effect graph legacy blur blocked layer IDs mismatch")
    expected_local_contrast = sample.get("expected_authored_effect_graph_local_contrast_count")
    if expected_local_contrast is not None:
        if local_contrast_count != int(expected_local_contrast):
            failures.append("authored effect graph Local Contrast count mismatch")
    expected_opacity = sample.get("expected_authored_effect_graph_opacity_count")
    if expected_opacity is not None:
        if opacity_count != int(expected_opacity):
            failures.append("authored effect graph Opacity count mismatch")
    expected_opacity_layers = sample.get("expected_authored_effect_graph_opacity_layer_ids")
    if expected_opacity_layers is not None:
        if (opacity_layer_ids or []) != sorted(expected_opacity_layers):
            failures.append("authored effect graph Opacity layer IDs mismatch")
    expected_workshop_shadow = sample.get(
        "expected_authored_effect_graph_workshop_shadow_count"
    )
    if expected_workshop_shadow is not None:
        if workshop_shadow_count != int(expected_workshop_shadow):
            failures.append("authored effect graph Workshop Shadow count mismatch")
    expected_shake = sample.get("expected_authored_effect_graph_shake_count")
    if expected_shake is not None:
        if shake_count != int(expected_shake):
            failures.append("authored effect graph Shake count mismatch")
    expected_route_only = sample.get("expected_route_only_effect_count")
    if expected_route_only is not None:
        if route_only_effect_count != int(expected_route_only):
            failures.append("offscreen route-only effect count mismatch")
    chain_metrics = chain_metrics or {"chain_count": None, "stage_count": None}
    for sample_key, metric_key, label in (
        ("expected_authored_effect_graph_chain_count", "chain_count", "chain count"),
        ("expected_authored_effect_graph_stage_count", "stage_count", "stage count"),
    ):
        if sample_key in sample and chain_metrics[metric_key] != int(sample[sample_key]):
            failures.append(f"authored effect graph {label} mismatch")
    return failures


def named_target_binding_failures(
    sample: dict[str, Any],
    planned_count: int,
    metrics: dict[str, Any],
) -> list[str]:
    succeeded = set(metrics["succeeded_layer_ids"])
    failures: list[str] = []
    if len(succeeded) < planned_count:
        failures.append("named target binding execution below planned count")
    for layer_id in sample.get("required_named_target_binding_succeeded_layer_ids", []):
        if layer_id not in succeeded:
            failures.append(f"named target consumer {layer_id} binding should succeed")
    return failures


def solid_runtime_failures(
    sample: dict[str, Any],
    metrics: dict[str, Any],
) -> list[str]:
    failures: list[str] = []
    requires_count_evidence = (
        "expected_solid_candidates" in sample
        or bool(sample.get("required_solid_loaded_layer_ids"))
    )
    if requires_count_evidence and not metrics["has_count_evidence"]:
        failures.append("solid layer count evidence missing")
    elif "expected_solid_candidates" in sample:
        if metrics["candidates"] != int(sample["expected_solid_candidates"]):
            failures.append("solid layer candidate count mismatch")

    loaded_layer_ids = set(metrics["loaded_layer_ids"])
    for layer_id in sample.get("required_solid_loaded_layer_ids", []):
        if layer_id not in loaded_layer_ids:
            failures.append(f"solid layer {layer_id} should be loaded")
    return failures


def particle_runtime_failures(
    sample: dict[str, Any],
    metrics: dict[str, Any],
) -> list[str]:
    failures: list[str] = []
    requires_load_evidence = (
        "minimum_particle_loaded" in sample
        or "expected_particle_candidates" in sample
        or bool(sample.get("required_particle_loaded_layer_ids"))
    )
    if requires_load_evidence and not metrics["has_load_evidence"]:
        failures.append("particle load evidence missing")
    else:
        if metrics["loaded"] < int(sample.get("minimum_particle_loaded", 0)):
            failures.append("particle loaded count below minimum")
        expected_candidates = sample.get("expected_particle_candidates")
        if expected_candidates is not None and metrics["candidates"] != int(expected_candidates):
            failures.append("particle candidate count mismatch")

    if "minimum_particle_initial_live" in sample:
        if not metrics["has_initial_live_evidence"]:
            failures.append("particle initial live evidence missing")
        elif metrics["initial_live"] < int(sample["minimum_particle_initial_live"]):
            failures.append("particle initial live count below minimum")
    visibility_expectations = {
        "expected_particle_authored": "authored",
        "expected_particle_visible": "visible",
        "expected_particle_skipped_hidden": "skipped_hidden",
    }
    if any(key in sample for key in visibility_expectations) and not metrics["has_visibility_evidence"]:
        failures.append("particle visibility evidence missing")
    else:
        for expectation, metric in visibility_expectations.items():
            if expectation in sample and metrics[metric] != int(sample[expectation]):
                failures.append(f"particle {metric} count mismatch")
    loaded_layer_ids = set(metrics["loaded_layer_ids"])
    for layer_id in sample.get("required_particle_loaded_layer_ids", []):
        if layer_id not in loaded_layer_ids:
            failures.append(f"particle layer {layer_id} should be loaded")
    return failures


def append_property_arguments(
    command: list[str],
    property_overrides: Any,
    live_property_overrides: Any,
) -> None:
    arguments = [
        (property_overrides, "--mwx-debug-scene-properties-json"),
        (live_property_overrides, "--mwx-debug-scene-live-properties-json"),
    ]
    for values, flag in arguments:
        if isinstance(values, dict) and values:
            command.extend([
                flag,
                json.dumps(values, ensure_ascii=False, separators=(",", ":")),
            ])


def live_property_update_metrics(log_text: str) -> dict[str, Any] | None:
    match = LIVE_PROPERTY_UPDATE_RE.search(log_text)
    if match is None:
        return None

    def window_numbers(raw: str) -> list[int]:
        return [int(value) for value in raw.split(",") if value]

    return {
        "accepted": match.group("accepted") == "true",
        "surfaces_before": int(match.group("before")),
        "surfaces_after": int(match.group("after")),
        "windows_before": window_numbers(match.group("windows_before")),
        "windows_after": window_numbers(match.group("windows_after")),
        "keys": [value for value in match.group("keys").split(",") if value],
    }


def live_property_update_failures(
    requested: Any,
    metrics: dict[str, Any] | None,
) -> list[str]:
    if not isinstance(requested, dict) or not requested:
        return []
    if metrics is None:
        return ["live property update evidence missing"]

    failures: list[str] = []
    if not metrics["accepted"]:
        failures.append("live property update rejected")
    if metrics["surfaces_before"] != metrics["surfaces_after"]:
        failures.append("live property update changed Scene surface count")
    if metrics["windows_before"] != metrics["windows_after"]:
        failures.append("live property update replaced Scene windows")
    if metrics["keys"] != sorted(requested):
        failures.append("live property update key evidence mismatch")
    return failures


def live_property_output_failures(
    sample: dict[str, Any],
    motion: dict[str, Any] | None,
) -> list[str]:
    minimum = sample.get("minimum_live_changed_ratio")
    if minimum is None:
        return []
    if motion is None or motion["changed_ratio"] < float(minimum):
        return ["live property output evidence below minimum"]
    return []


def run_sample(
    runtime_binary: Path,
    sample_root: Path,
    sample: dict[str, Any],
    output_dir: Path,
    duration: float,
) -> dict[str, Any]:
    sample_id = str(sample["id"])
    source = sample_root / "Scene" / sample_id
    result_dir = output_dir / "results" / sample_id
    runtime_sample = output_dir / "runtime-samples" / sample_id
    runtime_home = output_dir / "runtime-homes" / sample_id
    result_dir.mkdir(parents=True)
    runtime_home.mkdir(parents=True)
    copy_sample(source, runtime_sample)
    for file_name in SAMPLE_ROOT_DERIVED_FILES:
        (runtime_sample / file_name).unlink(missing_ok=True)
    package_path = scene_package_path(source)
    if package_path is None:
        raise FileNotFoundError(f"Scene sample package is missing: {source}")

    hashes = {
        "project_sha256": sha256(source / "project.json"),
        "package_sha256": sha256(package_path),
    }
    failures: list[str] = []
    for key, actual in hashes.items():
        expected = sample.get(key)
        if expected and expected != actual:
            failures.append(f"{key} mismatch")

    app_log = result_dir / "app.log"
    command = [
        str(runtime_binary),
        "--mwx-debug-scene-root",
        str(runtime_sample),
        "--mwx-debug-scene-evidence-dir",
        str(result_dir),
        "--mwx-debug-scene-duration",
        str(duration),
    ]
    property_overrides = sample.get("property_overrides")
    live_property_overrides = sample.get("live_property_overrides")
    append_property_arguments(command, property_overrides, live_property_overrides)
    environment = os.environ.copy()
    environment["HOME"] = str(runtime_home)
    environment["CFFIXED_USER_HOME"] = str(runtime_home)
    timed_out = False
    with app_log.open("w", encoding="utf-8") as log_handle:
        process = subprocess.Popen(
            command,
            cwd=output_dir,
            env=environment,
            stdout=log_handle,
            stderr=subprocess.STDOUT,
            text=True,
        )
        try:
            exit_code = process.wait(timeout=duration + 20)
        except subprocess.TimeoutExpired:
            timed_out = True
            process.terminate()
            try:
                exit_code = process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                exit_code = process.wait(timeout=5)

    log_text = app_log.read_text(encoding="utf-8", errors="replace")
    preview_log = result_dir / "scene-preview.log"
    preview_text = preview_log.read_text(encoding="utf-8", errors="replace") if preview_log.is_file() else ""
    ready_match = READY_RE.search(log_text)
    interpretation_match = INTERPRETATION_RE.search(log_text)
    stopped_match = STOPPED_RE.search(log_text)
    live_property_update = live_property_update_metrics(log_text)
    loaded_match = LOADED_RE.search(preview_text)
    loaded = int(loaded_match.group("loaded")) if loaded_match else 0
    total = int(loaded_match.group("total")) if loaded_match else 0
    loaded_ratio = loaded / total if total else 0.0
    text_loaded_match = TEXT_LOADED_RE.search(preview_text)
    text_loaded = int(text_loaded_match.group("loaded")) if text_loaded_match else 0
    text_total = int(text_loaded_match.group("total")) if text_loaded_match else 0
    text_loaded_layer_ids = [int(match.group("id")) for match in TEXT_LAYER_OK_RE.finditer(preview_text)]
    solid_runtime = solid_runtime_metrics(preview_text)
    utility_runtime = utility_runtime_metrics(preview_text)
    utility_capture_execution = utility_capture_execution_metrics(log_text)
    authored_effect_graph_execution = authored_effect_graph_execution_metrics(log_text)
    authored_effect_graph_legacy_blur_blocked = (
        authored_effect_graph_legacy_blur_blocked_layer_ids(preview_text)
    )
    authored_effect_graph_local_contrast = authored_effect_graph_local_contrast_count(
        preview_text
    )
    authored_effect_graph_opacity = authored_effect_graph_opacity_count(preview_text)
    authored_effect_graph_opacity_layers = authored_effect_graph_opacity_layer_ids(
        preview_text
    )
    authored_effect_graph_workshop_shadow = authored_effect_graph_workshop_shadow_count(
        preview_text
    )
    authored_effect_graph_shake = authored_effect_graph_shake_count(preview_text)
    authored_effect_graph_chain = authored_effect_graph_chain_metrics(preview_text)
    route_only_effect_count = preview_text.count("offscreen route-only")
    named_target_capture_execution = named_target_capture_execution_metrics(log_text)
    named_target_binding_execution = named_target_binding_execution_metrics(log_text)
    image_blend_runtime = image_blend_runtime_metrics(preview_text, log_text)
    particle_runtime = particle_runtime_metrics(preview_text)
    camera_match = CAMERA_RE.search(preview_text)
    ready_snapshot = result_dir / "scene-ready-window.png"
    after_snapshot = result_dir / "scene-after-window.png"
    ready_non_black = png_has_non_black_pixel(ready_snapshot)
    after_non_black = png_has_non_black_pixel(after_snapshot)
    flat_border_ratio = {
        "ready": png_flat_border_ratio(ready_snapshot),
        "after": png_flat_border_ratio(after_snapshot),
    }
    motion = png_motion_metrics(ready_snapshot, after_snapshot)
    interpretation_path = (
        Path(interpretation_match.group("path").strip())
        if interpretation_match is not None
        else Path("-")
    )
    interpretation = interpretation_metrics(interpretation_path)
    sample_root_residue = [
        file_name
        for file_name in SAMPLE_ROOT_DERIVED_FILES
        if (runtime_sample / file_name).exists()
    ]

    if timed_out:
        failures.append("process timeout")
    if exit_code != 0:
        failures.append(f"process exit {exit_code}")
    if ready_match is None:
        failures.append("missing ready event")
    elif int(ready_match.group("surfaces")) < 1:
        failures.append("no Scene surface")
    if interpretation_match is None:
        failures.append("missing cache interpretation path")
    else:
        interpretation_cache_root = (
            runtime_home / "Library/Caches/MyWallpaperX/SteamWorkshopScene"
        ).resolve()
        try:
            interpretation_path.resolve().relative_to(interpretation_cache_root)
        except ValueError:
            failures.append("Scene interpretation path is outside package cache")
    if sample_root_residue:
        failures.append(
            "Scene sample root contains derived files: " + ", ".join(sample_root_residue)
        )
    if stopped_match is None or int(stopped_match.group("after")) != 0:
        failures.append("Scene surfaces not released")
    failures.extend(live_property_update_failures(
        live_property_overrides,
        live_property_update,
    ))
    if "phase=snapshot-failed" in log_text:
        failures.append("window snapshot failed")
    if camera_match is None or camera_match.group("projection") != "cover":
        failures.append("camera projection evidence missing")
    expected_parallax = sample.get("expected_camera_parallax")
    if expected_parallax is not None:
        actual_parallax = camera_match and camera_match.group("parallax") == "true"
        if actual_parallax != bool(expected_parallax):
            failures.append("camera parallax state mismatch")
    minimum_parallax_layers = int(sample.get("minimum_authored_parallax_layer_count", 0))
    if interpretation["authored_parallax_layer_count"] < minimum_parallax_layers:
        failures.append("authored parallax layer count below minimum")
    if loaded_ratio < float(sample.get("minimum_loaded_ratio", 0)):
        failures.append(f"loaded ratio {loaded_ratio:.3f} below minimum")
    if text_loaded < int(sample.get("minimum_text_loaded", 0)):
        failures.append("text texture count below minimum")
    if "expected_text_candidates" in sample and text_total != int(sample["expected_text_candidates"]):
        failures.append("text candidate count mismatch")
    for layer_id in sample.get("required_text_loaded_layer_ids", []):
        if layer_id not in text_loaded_layer_ids:
            failures.append(f"text layer {layer_id} should be loaded")
    failures.extend(solid_runtime_failures(sample, solid_runtime))
    failures.extend(utility_runtime_failures(sample, utility_runtime))
    failures.extend(authored_effect_graph_failures(
        sample,
        authored_effect_graph_execution,
        authored_effect_graph_legacy_blur_blocked,
        authored_effect_graph_local_contrast,
        authored_effect_graph_chain,
        workshop_shadow_count=authored_effect_graph_workshop_shadow,
        shake_count=authored_effect_graph_shake,
        opacity_count=authored_effect_graph_opacity,
        route_only_effect_count=route_only_effect_count,
        opacity_layer_ids=authored_effect_graph_opacity_layers,
    ))
    succeeded_capture_ids = set(utility_capture_execution["succeeded_layer_ids"])
    if len(succeeded_capture_ids) < utility_runtime["capture_planned"]:
        failures.append("utility capture execution below planned count")
    for layer_id in sample.get("required_utility_capture_succeeded_layer_ids", []):
        if layer_id not in succeeded_capture_ids:
            failures.append(f"utility layer {layer_id} capture should succeed")
    succeeded_named_target_ids = set(named_target_capture_execution["succeeded_layer_ids"])
    if len(succeeded_named_target_ids) < utility_runtime["named_target_planned"]:
        failures.append("named target capture execution below planned count")
    for layer_id in sample.get("required_named_target_capture_succeeded_layer_ids", []):
        if layer_id not in succeeded_named_target_ids:
            failures.append(f"named target layer {layer_id} capture should succeed")
    failures.extend(named_target_binding_failures(
        sample,
        utility_runtime["named_binding_planned"],
        named_target_binding_execution,
    ))
    failures.extend(image_blend_runtime_failures(sample, image_blend_runtime))
    failures.extend(particle_runtime_failures(sample, particle_runtime))
    blur_runtime_count = preview_text.count("effect runtime gaussian-blur;")
    if blur_runtime_count < int(sample.get("minimum_gaussian_blur_runtime_count", 0)):
        failures.append("gaussian blur runtime count below minimum")
    precise_blur_runtime_count = preview_text.count("effect runtime gaussian-blur-precise;")
    if precise_blur_runtime_count < int(sample.get("minimum_precise_blur_runtime_count", 0)):
        failures.append("precise gaussian blur runtime count below minimum")
    authored_opacity_runtime_count = preview_text.count("effect runtime opacity-authored;")
    if authored_opacity_runtime_count < int(
        sample.get("minimum_authored_opacity_runtime_count", 0)
    ):
        failures.append("authored opacity runtime count below minimum")
    skipped_composite_count = preview_text.count("unsupported composite skipped;")
    if skipped_composite_count < int(sample.get("minimum_skipped_composite_count", 0)):
        failures.append("unsupported composite fallback count below minimum")
    maximum_skipped_composite_count = sample.get("maximum_skipped_composite_count")
    if maximum_skipped_composite_count is not None:
        if skipped_composite_count > int(maximum_skipped_composite_count):
            failures.append("unsupported composite fallback count above maximum")
    perspective_opacity_count = preview_text.count("effect runtime perspective-opacity;")
    if perspective_opacity_count < int(sample.get("minimum_perspective_opacity_runtime_count", 0)):
        failures.append("perspective opacity runtime count below minimum")
    water_ripple_normal_count = preview_text.count("effect runtime waterripple-normal;")
    if water_ripple_normal_count < int(sample.get("minimum_water_ripple_normal_runtime_count", 0)):
        failures.append("normal-map water ripple runtime count below minimum")
    water_ripple_normal_load_count = preview_text.count("waterripple normal OK")
    if water_ripple_normal_load_count < int(sample.get("minimum_water_ripple_normal_load_count", 0)):
        failures.append("normal-map water ripple texture load count below minimum")
    legacy_water_ripple_count = preview_text.count("effect runtime waterripple-legacy;")
    if legacy_water_ripple_count < int(sample.get("minimum_legacy_water_ripple_runtime_count", 0)):
        failures.append("legacy water ripple runtime count below minimum")
    maximum_legacy_water_ripple_count = sample.get("maximum_legacy_water_ripple_runtime_count")
    if maximum_legacy_water_ripple_count is not None:
        if legacy_water_ripple_count > int(maximum_legacy_water_ripple_count):
            failures.append("legacy water ripple runtime count above maximum")
    legacy_waterwaves_count = preview_text.count("effect runtime waterwaves-legacy;")
    if legacy_waterwaves_count < int(sample.get("minimum_legacy_waterwaves_runtime_count", 0)):
        failures.append("legacy waterwaves runtime count below minimum")
    maximum_legacy_waterwaves_count = sample.get("maximum_legacy_waterwaves_runtime_count")
    if maximum_legacy_waterwaves_count is not None:
        if legacy_waterwaves_count > int(maximum_legacy_waterwaves_count):
            failures.append("legacy waterwaves runtime count above maximum")
    sprite_animation_count = preview_text.count("; sprite animation frames=")
    if sprite_animation_count < int(sample.get("minimum_sprite_animation_count", 0)):
        failures.append("sprite animation runtime count below minimum")
    color_blend_mode_9_count = preview_text.count("layer color blend mode=9")
    if color_blend_mode_9_count < int(sample.get("minimum_color_blend_mode_9_count", 0)):
        failures.append("layer color blend mode 9 count below minimum")
    if interpretation["format_version"] is None:
        failures.append("Scene interpretation evidence missing or invalid")
    interpretation_expectations = {
        "expected_interpretation_format": "format_version",
        "expected_shader_contract_count": "shader_contract_count",
        "expected_shader_contract_authored_count": "shader_contract_authored_count",
        "expected_shader_contract_builtin_count": "shader_contract_builtin_count",
        "expected_shader_contract_stage_count": "shader_contract_stage_count",
        "expected_shader_contract_diagnostic_count": "shader_contract_diagnostic_count",
        "expected_effect_texture_slot_count": "effect_texture_slot_count",
        "expected_effect_texture_slot_hole_count": "effect_texture_slot_hole_count",
        "expected_effect_combo_entry_count": "effect_combo_entry_count",
        "expected_material_texture_slot_count": "material_texture_slot_count",
        "expected_material_texture_slot_hole_count": "material_texture_slot_hole_count",
        "expected_material_combo_entry_count": "material_combo_entry_count",
        "expected_effect_definition_count": "effect_definition_count",
        "expected_effect_definition_pass_count": "effect_definition_pass_count",
        "expected_effect_definition_material_pass_count": "effect_definition_material_pass_count",
        "expected_effect_definition_fbo_count": "effect_definition_fbo_count",
        "expected_effect_definition_copy_command_count": "effect_definition_copy_command_count",
        "expected_effect_definition_swap_command_count": "effect_definition_swap_command_count",
        "expected_effect_definition_diagnostic_count": "effect_definition_diagnostic_count",
        "expected_effect_graph_layer_count": "effect_graph_layer_count",
        "expected_effect_graph_effect_count": "effect_graph_effect_count",
        "expected_effect_graph_node_count": "effect_graph_node_count",
        "expected_effect_graph_material_node_count": "effect_graph_material_node_count",
        "expected_effect_graph_copy_node_count": "effect_graph_copy_node_count",
        "expected_effect_graph_swap_node_count": "effect_graph_swap_node_count",
        "expected_effect_graph_render_target_count": "effect_graph_render_target_count",
        "expected_effect_graph_blocker_count": "effect_graph_blocker_count",
        "expected_effect_graph_unblocked_layer_count": "effect_graph_unblocked_layer_count",
        "expected_visible_layer_count": "visible_layer_count",
        "expected_root_layer_count": "root_layer_count",
        "expected_child_edge_count": "child_edge_count",
        "expected_parent_layer_count": "parent_layer_count",
        "expected_max_hierarchy_depth": "max_hierarchy_depth",
        "expected_effective_visible_layer_count": "effective_visible_layer_count",
        "expected_solid_layer_count": "solid_layer_count",
        "expected_authored_solid_color_layer_count": "authored_solid_color_layer_count",
        "expected_effective_visible_solid_layer_count": "effective_visible_solid_layer_count",
        "expected_built_in_reference_count": "built_in_reference_count",
        "expected_missing_resource_count": "missing_resource_count",
        "expected_composition_layer_count": "composition_layer_count",
        "expected_project_layer_count": "project_layer_count",
        "expected_fullscreen_layer_count": "fullscreen_layer_count",
        "expected_dependency_edge_count": "dependency_edge_count",
    }
    for expectation, metric in interpretation_expectations.items():
        if expectation in sample and interpretation[metric] != int(sample[expectation]):
            failures.append(f"Scene interpretation {metric} mismatch")
    expected_effect_graph_sha256 = sample.get("expected_effect_graph_sha256")
    if expected_effect_graph_sha256 is not None:
        if interpretation["effect_graph_sha256"] != expected_effect_graph_sha256:
            failures.append("Scene interpretation effect graph sha256 mismatch")
    expected_opacity_candidates = sample.get(
        "expected_stock_opacity_single_effect_candidate_layer_ids"
    )
    if expected_opacity_candidates is not None:
        if (
            interpretation["stock_opacity_single_effect_candidate_layer_ids"]
            != sorted(expected_opacity_candidates)
        ):
            failures.append("Scene interpretation stock Opacity candidate IDs mismatch")
    expected_shader_contract_aggregate_sha256 = sample.get(
        "expected_shader_contract_aggregate_sha256"
    )
    if expected_shader_contract_aggregate_sha256 is not None:
        if (
            interpretation["shader_contract_aggregate_sha256"]
            != expected_shader_contract_aggregate_sha256
        ):
            failures.append("Scene interpretation shader contract aggregate sha256 mismatch")
    expected_text_value = sample.get("expected_text_value")
    if expected_text_value is not None and expected_text_value not in interpretation["text_values"]:
        failures.append("Scene interpretation text property mismatch")
    visible_layer_ids = set(interpretation["visible_layer_ids"])
    for layer_id in sample.get("required_visible_layer_ids", []):
        if layer_id not in visible_layer_ids:
            failures.append(f"Scene property layer {layer_id} should be visible")
    for layer_id in sample.get("required_hidden_layer_ids", []):
        if layer_id in visible_layer_ids:
            failures.append(f"Scene property layer {layer_id} should be hidden")
    effective_visible_layer_ids = set(interpretation["effective_visible_layer_ids"])
    for layer_id in sample.get("required_effectively_visible_layer_ids", []):
        if layer_id not in effective_visible_layer_ids:
            failures.append(f"Scene layer {layer_id} should be effectively visible")
    for layer_id in sample.get("required_effectively_hidden_layer_ids", []):
        if layer_id in effective_visible_layer_ids:
            failures.append(f"Scene layer {layer_id} should be effectively hidden")
    solid_layer_ids = set(interpretation["solid_layer_ids"])
    for layer_id in sample.get("required_solid_layer_ids", []):
        if layer_id not in solid_layer_ids:
            failures.append(f"Scene solid layer {layer_id} is missing")
    effective_visible_solid_layer_ids = set(
        interpretation["effective_visible_solid_layer_ids"]
    )
    for layer_id in sample.get("required_effectively_visible_solid_layer_ids", []):
        if layer_id not in effective_visible_solid_layer_ids:
            failures.append(f"Scene solid layer {layer_id} should be effectively visible")
    effect_files = set(interpretation["effect_files"])
    for effect_file in sample.get("required_effect_files", []):
        if effect_file not in effect_files:
            failures.append(f"Scene effect file missing: {effect_file}")
    bloom_runtime_count = preview_text.count("effect runtime bloom")
    if bloom_runtime_count < int(sample.get("minimum_bloom_runtime_count", 0)):
        failures.append("bloom runtime count below minimum")
    if not ready_non_black or not after_non_black:
        failures.append("non-black window evidence missing")
    if sample.get("requires_motion"):
        minimum_changed_ratio = float(sample.get("minimum_changed_ratio", 0))
        if motion is None or motion["changed_ratio"] < minimum_changed_ratio:
            failures.append("animated output evidence below minimum")
    failures.extend(live_property_output_failures(sample, motion))
    maximum_changed_ratio = sample.get("maximum_changed_ratio")
    if maximum_changed_ratio is not None:
        if motion is None or motion["changed_ratio"] > float(maximum_changed_ratio):
            failures.append("static output evidence above maximum")
    maximum_flat_border_ratio = sample.get("maximum_flat_border_ratio")
    if maximum_flat_border_ratio is not None:
        ratios = [value for value in flat_border_ratio.values() if value is not None]
        if len(ratios) != 2 or max(ratios) > float(maximum_flat_border_ratio):
            failures.append("flat border evidence above maximum")

    return {
        "id": sample_id,
        "title": sample.get("title"),
        "capabilities": sample.get("capabilities", []),
        "property_overrides": property_overrides if isinstance(property_overrides, dict) else {},
        "live_property_overrides": (
            live_property_overrides if isinstance(live_property_overrides, dict) else {}
        ),
        "passed": not failures,
        "failures": failures,
        "exit_code": exit_code,
        "timed_out": timed_out,
        "hashes": hashes,
        "package_file": package_path.name,
        "runtime_sample": str(runtime_sample),
        "runtime_home": str(runtime_home),
        "evidence": {
            "app_log": str(app_log),
            "preview_log": str(preview_log),
            "interpretation": str(interpretation_path),
            "sample_root_residue": sample_root_residue,
            "ready_snapshot": str(ready_snapshot),
            "after_snapshot": str(after_snapshot),
            "ready_non_black": ready_non_black,
            "after_non_black": after_non_black,
            "flat_border_ratio": flat_border_ratio,
            "motion": motion,
        },
        "runtime": {
            "layers": int(ready_match.group("layers")) if ready_match else None,
            "image_layers": int(ready_match.group("images")) if ready_match else None,
            "effects": int(ready_match.group("effects")) if ready_match else None,
            "surfaces": int(ready_match.group("surfaces")) if ready_match else None,
            "live_property_update": live_property_update,
            "loaded_textures": loaded,
            "texture_candidates": total,
            "loaded_ratio": round(loaded_ratio, 4),
            "loaded_textures_text": text_loaded,
            "text_candidates": text_total,
            "text_loaded_layer_ids": text_loaded_layer_ids,
            "loaded_solid_layers": solid_runtime["loaded"],
            "solid_candidates": solid_runtime["candidates"],
            "solid_loaded_ratio": round(solid_runtime["loaded_ratio"], 4),
            "solid_loaded_layer_ids": solid_runtime["loaded_layer_ids"],
            "utility_candidates": utility_runtime["candidates"],
            "utility_capture_planned": utility_runtime["capture_planned"],
            "utility_dependency_edges": utility_runtime["dependency_edges"],
            "utility_named_consumers": utility_runtime["named_consumers"],
            "utility_named_target_planned": utility_runtime["named_target_planned"],
            "utility_named_binding_planned": utility_runtime["named_binding_planned"],
            "utility_named_target_gaps": utility_runtime["named_target_gaps"],
            "utility_layers": utility_runtime["layers"],
            "utility_capture_succeeded_layer_ids": utility_capture_execution["succeeded_layer_ids"],
            "utility_capture_failed_layer_ids": utility_capture_execution["failed_layer_ids"],
            "authored_effect_graph_succeeded_layer_ids": authored_effect_graph_execution["succeeded_layer_ids"],
            "authored_effect_graph_failed_layer_ids": authored_effect_graph_execution["failed_layer_ids"],
            "authored_effect_graph_legacy_blur_blocked_layer_ids": authored_effect_graph_legacy_blur_blocked,
            "authored_effect_graph_local_contrast_count": authored_effect_graph_local_contrast,
            "authored_effect_graph_opacity_count": authored_effect_graph_opacity,
            "authored_effect_graph_opacity_layer_ids": authored_effect_graph_opacity_layers,
            "authored_effect_graph_workshop_shadow_count": authored_effect_graph_workshop_shadow,
            "authored_effect_graph_shake_count": authored_effect_graph_shake,
            "authored_effect_graph_chain_count": authored_effect_graph_chain["chain_count"],
            "authored_effect_graph_stage_count": authored_effect_graph_chain["stage_count"],
            "named_target_capture_succeeded_layer_ids": named_target_capture_execution["succeeded_layer_ids"],
            "named_target_capture_failed_layer_ids": named_target_capture_execution["failed_layer_ids"],
            "named_target_binding_succeeded_layer_ids": named_target_binding_execution["succeeded_layer_ids"],
            "named_target_binding_failed_layer_ids": named_target_binding_execution["failed_layer_ids"],
            "image_blend_planned": image_blend_runtime["planned"],
            "image_blend_succeeded_layer_ids": image_blend_runtime["succeeded_layer_ids"],
            "image_blend_failed_layer_ids": image_blend_runtime["failed_layer_ids"],
            "loaded_particle_layers": particle_runtime["loaded"],
            "particle_candidates": particle_runtime["candidates"],
            "particle_loaded_ratio": round(particle_runtime["loaded_ratio"], 4),
            "particle_initial_live": particle_runtime["initial_live"],
            "particle_authored": particle_runtime["authored"],
            "particle_visible": particle_runtime["visible"],
            "particle_skipped_hidden": particle_runtime["skipped_hidden"],
            "particle_loaded_layer_ids": particle_runtime["loaded_layer_ids"],
            "camera_projection": camera_match.group("projection") if camera_match else None,
            "camera_parallax": camera_match.group("parallax") == "true" if camera_match else None,
            "camera_parallax_amount": float(camera_match.group("amount")) if camera_match else None,
            "camera_parallax_delay": (
                float(camera_match.group("delay"))
                if camera_match and camera_match.group("delay") is not None
                else None
            ),
            "camera_parallax_mouse_influence": float(camera_match.group("influence")) if camera_match else None,
            "offscreen_route_count": preview_text.count("offscreen skeleton"),
            "gaussian_blur_runtime_count": blur_runtime_count,
            "precise_blur_runtime_count": precise_blur_runtime_count,
            "skipped_unsupported_composite_count": skipped_composite_count,
            "perspective_opacity_runtime_count": perspective_opacity_count,
            "water_ripple_normal_runtime_count": water_ripple_normal_count,
            "water_ripple_normal_load_count": water_ripple_normal_load_count,
            "legacy_water_ripple_runtime_count": legacy_water_ripple_count,
            "legacy_waterwaves_runtime_count": legacy_waterwaves_count,
            "sprite_animation_count": sprite_animation_count,
            "color_blend_mode_9_count": color_blend_mode_9_count,
            "bloom_runtime_count": bloom_runtime_count,
            "route_only_effect_count": route_only_effect_count,
            "interpretation": interpretation,
        },
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", required=True, type=Path, help="signed MyWallpaperX executable")
    parser.add_argument("--sample-root", required=True, type=Path, help="isolated root containing Scene/<id>")
    parser.add_argument(
        "--matrix",
        type=Path,
        default=Path(__file__).with_name("scene_wallpaper_sample_matrix.json"),
    )
    parser.add_argument("--output-dir", required=True, type=Path)
    parser.add_argument("--duration", type=float, default=7)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    output_dir = require_fresh_output_dir(args.output_dir.expanduser().resolve())
    matrix_path = args.matrix.expanduser().resolve()
    matrix = load_matrix(matrix_path)
    try:
        runtime_binary, app_identity = stage_signed_app(args.app, output_dir)
    except AppIdentityError as error:
        print(f"Scene benchmark precondition failed: {error}", file=sys.stderr)
        return 2

    results = [
        run_sample(
            runtime_binary=runtime_binary,
            sample_root=args.sample_root.expanduser().resolve(),
            sample=sample,
            output_dir=output_dir,
            duration=max(args.duration, 5),
        )
        for sample in matrix["samples"]
    ]
    try:
        verify_staged_app(app_identity)
    except AppIdentityError as error:
        for result in results:
            result["failures"].append(f"staged app identity failure: {error}")
            result["passed"] = False

    passed = all(result["passed"] for result in results)
    report = {
        "schema_version": 1,
        "matrix": matrix["name"],
        "matrix_path": str(matrix_path),
        "matrix_sha256": sha256(matrix_path),
        "command": sys.argv,
        "app_identity": app_identity,
        "sample_root": str(args.sample_root.expanduser().resolve()),
        "summary": {
            "passed": passed,
            "sample_count": len(results),
            "passed_count": sum(result["passed"] for result in results),
        },
        "samples": results,
    }
    report_path = output_dir / "report.json"
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Scene benchmark {'PASS' if passed else 'FAIL'}: {report_path}")
    for result in results:
        print(
            f"{result['id']}: {'PASS' if result['passed'] else 'FAIL'} "
            f"loaded={result['runtime']['loaded_ratio']:.3f} failures={result['failures']}"
        )
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
