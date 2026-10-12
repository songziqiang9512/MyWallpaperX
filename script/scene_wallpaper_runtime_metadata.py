"""Parse prepared Scene runtime, shader-contract and resource metadata."""

from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path
from typing import Any


def pass_metadata_metrics(passes: list[Any]) -> tuple[int, int, int]:
    slot_count = 0
    slot_holes = 0
    combo_count = 0
    for item in passes:
        if not isinstance(item, dict):
            raise ValueError("Scene runtime evidence pass is not an object")
        slots = item.get("textureSlots")
        combos = item.get("combos")
        if not isinstance(slots, list) or any(slot is not None and not isinstance(slot, str) for slot in slots):
            raise ValueError("Scene runtime evidence textureSlots has an invalid shape")
        if not isinstance(combos, dict) or any(type(value) is not int for value in combos.values()):
            raise ValueError("Scene runtime evidence combos has an invalid shape")
        slot_count += len(slots)
        slot_holes += sum(slot is None for slot in slots)
        combo_count += len(combos)
    return slot_count, slot_holes, combo_count

def shader_contract_metrics(contracts: Any) -> dict[str, Any]:
    if not isinstance(contracts, list):
        raise ValueError("Scene runtime evidence shaderContracts has an invalid shape")

    authored_count = 0
    builtin_count = 0
    stage_count = 0
    diagnostic_count = 0
    aggregate_entries: list[list[str]] = []
    identities: set[str] = set()
    for contract in contracts:
        if not isinstance(contract, dict):
            raise ValueError("Scene runtime evidence shader contract is not an object")
        identity = contract.get("identity")
        source_kind = contract.get("sourceKind")
        stages = contract.get("stages")
        diagnostics = contract.get("diagnostics")
        canonical_sha256 = contract.get("canonicalSHA256")
        if not isinstance(identity, str) or not identity:
            raise ValueError("Scene runtime evidence shader contract identity has an invalid shape")
        if identity in identities:
            raise ValueError("Scene runtime evidence shader contract identity is duplicated")
        identities.add(identity)
        if source_kind not in {"authoredSource", "hostBuiltin"}:
            raise ValueError("Scene runtime evidence shader contract sourceKind has an invalid shape")
        if not isinstance(stages, list):
            raise ValueError("Scene runtime evidence shader contract stages has an invalid shape")
        if not isinstance(diagnostics, list):
            raise ValueError("Scene runtime evidence shader contract diagnostics has an invalid shape")
        if not isinstance(canonical_sha256, str) or re.fullmatch(
            r"[0-9a-f]{64}", canonical_sha256
        ) is None:
            raise ValueError(
                "Scene runtime evidence shader contract canonicalSHA256 has an invalid shape"
            )

        stage_kinds: set[str] = set()
        for stage in stages:
            if not isinstance(stage, dict):
                raise ValueError("Scene runtime evidence shader contract stage is not an object")
            kind = stage.get("kind")
            relative_path = stage.get("relativePath")
            source = stage.get("source")
            raw_sha256 = stage.get("rawSHA256")
            if kind not in {"vertex", "fragment"} or kind in stage_kinds:
                raise ValueError("Scene runtime evidence shader contract stage kind is invalid")
            stage_kinds.add(kind)
            if relative_path != f"shaders/{identity}.{'vert' if kind == 'vertex' else 'frag'}":
                raise ValueError("Scene runtime evidence shader contract stage path is invalid")
            if not isinstance(source, str) or not isinstance(raw_sha256, str):
                raise ValueError("Scene runtime evidence shader contract stage source is invalid")
            if raw_sha256 != hashlib.sha256(source.encode("utf-8")).hexdigest():
                raise ValueError("Scene runtime evidence shader contract stage rawSHA256 mismatch")

            for field in ("includes", "annotations", "declarations"):
                if not isinstance(stage.get(field), list):
                    raise ValueError(
                        f"Scene runtime evidence shader contract stage {field} is invalid"
                    )
            for include in stage["includes"]:
                if not isinstance(include, dict) or not isinstance(include.get("relativePath"), str):
                    raise ValueError("Scene runtime evidence shader contract include is invalid")
                if not isinstance(include.get("raw"), str) or type(include.get("line")) is not int:
                    raise ValueError("Scene runtime evidence shader contract include is invalid")
            for annotation in stage["annotations"]:
                marker = annotation.get("marker") if isinstance(annotation, dict) else None
                if not isinstance(annotation, dict) or "value" not in annotation:
                    raise ValueError("Scene runtime evidence shader contract annotation is invalid")
                if marker is not None and not isinstance(marker, str):
                    raise ValueError("Scene runtime evidence shader contract annotation is invalid")
                if not isinstance(annotation.get("raw"), str) or type(annotation.get("line")) is not int:
                    raise ValueError("Scene runtime evidence shader contract annotation is invalid")
            for declaration in stage["declarations"]:
                if not isinstance(declaration, dict) or declaration.get("kind") not in {
                    "uniform", "attribute", "varying"
                }:
                    raise ValueError("Scene runtime evidence shader contract declaration is invalid")
                if not all(isinstance(declaration.get(field), str) for field in ("type", "name", "raw")):
                    raise ValueError("Scene runtime evidence shader contract declaration is invalid")
                if type(declaration.get("line")) is not int:
                    raise ValueError("Scene runtime evidence shader contract declaration is invalid")
                if declaration.get("arraySuffix") is not None and not isinstance(
                    declaration.get("arraySuffix"), str
                ):
                    raise ValueError("Scene runtime evidence shader contract declaration is invalid")
                if declaration.get("arraySize") is not None and type(
                    declaration.get("arraySize")
                ) is not int:
                    raise ValueError("Scene runtime evidence shader contract declaration is invalid")

        diagnostic_codes = {
            "duplicateIdentity", "invalidReference", "pathEscape", "symlinkEscape",
            "missingVertexStage", "missingFragmentStage", "unreadableSource", "invalidUTF8",
            "malformedAnnotation",
        }
        for diagnostic in diagnostics:
            if not isinstance(diagnostic, dict) or diagnostic.get("code") not in diagnostic_codes:
                raise ValueError("Scene runtime evidence shader contract diagnostic is invalid")
            if not isinstance(diagnostic.get("message"), str):
                raise ValueError("Scene runtime evidence shader contract diagnostic is invalid")
            if diagnostic.get("relativePath") is not None and not isinstance(
                diagnostic.get("relativePath"), str
            ):
                raise ValueError("Scene runtime evidence shader contract diagnostic is invalid")
            if diagnostic.get("line") is not None and type(diagnostic.get("line")) is not int:
                raise ValueError("Scene runtime evidence shader contract diagnostic is invalid")
        if source_kind == "hostBuiltin" and (stages or diagnostics):
            raise ValueError("Scene runtime evidence host builtin shader contract is invalid")

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

def runtime_evidence_metrics(path: Path) -> dict[str, Any]:
    try:
        evidence = json.loads(path.read_text(encoding="utf-8"))
        payload = evidence["runtimeInput"]
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
            "schema_version": int(evidence["schemaVersion"]),
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
            "schema_version": None,
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
