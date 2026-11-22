#!/usr/bin/env python3

from __future__ import annotations

import json
import base64
import os
import shutil
import subprocess
import tempfile
import unittest
import sys
from pathlib import Path


SOURCE_SET_SCRIPT_ROOT = Path(__file__).resolve().parents[1]
if str(SOURCE_SET_SCRIPT_ROOT) not in sys.path:
    sys.path.insert(0, str(SOURCE_SET_SCRIPT_ROOT))

from scene_swift_source_sets import scene_swift_sources_by_basename
from script.tests.scene.test_scene_puppet_mesh import build_attachment_mdl
from script.tests.scene.test_scene_particle_assets import SWIFT_SOURCES as PARTICLE_GRAPH_SOURCES
from script.tests.test_scene_timeline_document import (
    SHADER_VALUE_NUMERIC_CASES, SHADER_VALUE_NESTED_CASES, assert_numeric_shader_values,
)


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SHADER_CONTRACT_RESOURCE_RESOLUTION_SOURCES = scene_swift_sources_by_basename(
    "shader_contract_resource_resolution"
)
SWIFT_SOURCES = [
    SHADER_CONTRACT_RESOURCE_RESOLUTION_SOURCES["SceneBuiltinShaderIdentity.swift"],
    SHADER_CONTRACT_RESOURCE_RESOLUTION_SOURCES["SceneJSONValue.swift"],
    SCENE_ROOT / "Format/SceneCompatibilityContext.swift",
    SCENE_ROOT / "Format/SceneDocument+ShaderValue.swift",
    SCENE_ROOT / "Format/SceneDocument+NumericParsing.swift",
    Path(__file__).resolve().parents[2] / "MyWallpaperX/Shared/WorkshopPropertyDisplayResolver.swift",
    SCENE_ROOT / "Format/SceneProject.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Properties/SceneUserProperty.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Properties/SceneUserPropertyDefinitionParser.swift",
    SHADER_CONTRACT_RESOURCE_RESOLUTION_SOURCES["SceneResourceIndex.swift"],
    SHADER_CONTRACT_RESOURCE_RESOLUTION_SOURCES["SceneResourceView.swift"],
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Assets/SceneAssetCatalog.swift",
    SCENE_ROOT / "Format/SceneMdlPuppetAttachmentReader.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneEffectDefinition.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneEffectTextureInput.swift",
    SCENE_ROOT / "Compilation/Material/SceneRenderTargetVocabulary.swift",
    SCENE_ROOT / "Resources/Textures/SceneNamedTextureReference.swift",
    SHADER_CONTRACT_RESOURCE_RESOLUTION_SOURCES["SceneShaderSourceGraph.swift"],
    SHADER_CONTRACT_RESOURCE_RESOLUTION_SOURCES[
        "SceneShaderLegacyAnnotationJSON.swift"
    ],
    SHADER_CONTRACT_RESOURCE_RESOLUTION_SOURCES["SceneShaderContract.swift"],
    SHADER_CONTRACT_RESOURCE_RESOLUTION_SOURCES[
        "SceneShaderSourceGraphBuilder.swift"
    ],
    SHADER_CONTRACT_RESOURCE_RESOLUTION_SOURCES[
        "SceneShaderSourceResolver.swift"
    ],
    SHADER_CONTRACT_RESOURCE_RESOLUTION_SOURCES[
        "SceneShaderContractLoader.swift"
    ],
    SHADER_CONTRACT_RESOURCE_RESOLUTION_SOURCES[
        "SceneShaderContractLoader+SourceGraph.swift"
    ],
]
SWIFT_SOURCES = list(dict.fromkeys([
    *SWIFT_SOURCES, *SHADER_CONTRACT_RESOURCE_RESOLUTION_SOURCES.values(), *PARTICLE_GRAPH_SOURCES,
    SCENE_ROOT / "Systems/Script/SceneScriptDynamicImageReferenceAnalysis.swift",
    SCENE_ROOT / "Systems/Properties/SceneLaunchOriginTransitionCompiler+SyntaxLexer.swift",
]))

HARNESS = r'''
import Foundation

enum SceneDocument {}

struct SceneRenderDescriptor {
    struct Link { let modelPath: String }
    let modelMaterialLinks: [Link]
}

enum AssetReadProbe { static var calls: [String: Int] = [:] }
enum ParticleParseProbe { static var calls = 0 }
enum CatalogRoleParseProbe {
    static var materials: [String: Int] = [:]
    static var effects: [String: Int] = [:]
    static var models: [String: Int] = [:]
}
enum ModelReferenceProbe { static var resolved: [String] = [] }
enum CatalogFixtureCancellation: Error { case requested }

struct SceneTimelineAnimation: Codable, Equatable {}

enum SceneDocumentLoader {}

@main
enum Harness {
    static func main() throws {
        let projectRoot = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let packageRoot = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        let stockRoot = URL(fileURLWithPath: CommandLine.arguments[3], isDirectory: true)
        let project = try SceneProjectLoader().load(from: projectRoot)
        let view = SceneResourceView(projectRootURL: projectRoot, packageRootURL: packageRoot,
                                     stockAssetsRootURL: stockRoot)
        var definitions: [String: SceneParticleAssetGraphLoader.PreparedDefinition] = [:]
        let catalog = try SceneAssetCatalogLoader().load(resourceView: view,
            referencedResourcePaths: ["models/util/solidlayer_depthtest.json", "models/workshop/bar.json",
                "models/puppet-owner.json", "models/broken-puppet-owner.json", "models/renamed-owner.json",
                "models/invalid.json", "materials/invalid.json", "effects/valid/effect.json",
                "effects/invalid/effect.json", "models/exact-material.json"],
            propertyCatalog: project.userProperties,
            scriptSources: ["export const __workshopId = '314'; export function init() { thisScene.createLayer('models/shared.json'); thisScene.createLayer({image: 'models/literal.json', name: String(1)}); }",
                "export function init() { thisScene.createLayer('models/' + 'literal.json'); thisScene.createLayer('models/' + 'only-computed.json'); }"],
            particlePaths: ["Particles/Root.JSON", "particles/hidden.json"],
            preparedParticleDefinition: { definitions[$0] = $1 }
        )
        let readsAfterCatalog = AssetReadProbe.calls
        let parsesAfterCatalog = ParticleParseProbe.calls
        let particleGraph = try SceneParticleAssetGraphLoader(resourceView: view, stockTextureBundleURL: nil)
            .load(rootPaths: ["particles/root.json"], materialPasses: [], preparedDefinitions: definitions)
        let selectedModels = catalog.models.map(\.relativePath)
        let dynamicAliases = SceneScriptDynamicImageReferenceAnalysis.references(
            in: "export const __workshopId = '314'; thisScene.createLayer('models/shared.json');",
            availableModelPaths: selectedModels) ?? []
        let model = catalog.models.first {
            $0.relativePath == "models/util/solidlayer_depthtest.json"
        }
        let barModel = catalog.models.first {
            $0.relativePath == "models/workshop/bar.json"
        }
        let tint = catalog.materials.first {
            $0.relativePath == "materials/workshop/bar.json"
        }?.passes.first?.constantShaderValues["g_TintColor"]
        let numericValues = catalog.materials.first {
            $0.relativePath == "materials/workshop/bar.json"
        }!.passes[0].constantShaderValues.mapValues { value -> [String: Any] in
            ["valueKind": value.valueKind, "rawValue": value.rawValue,
             "hasComponents": value.components != nil, "components": value.components ?? [],
             "userValueKind": value.userValueKind?.rawValue ?? "-",
             "hasTimeline": value.timeline != nil, "bindingKeys": value.bindingKeys,
             "script": value.scriptSource ?? "-",
             "speed": value.scriptProperties?["speed"]?.numberValue ?? -1]
        }
        let puppetModel = catalog.models.first { $0.relativePath == "models/puppet-owner.json" }
        let brokenPuppetModel = catalog.models.first { $0.relativePath == "models/broken-puppet-owner.json" }
        let renamedPuppetModel = catalog.models.first { $0.relativePath == "models/renamed-owner.json" }
        var result: [String: Any] = [
            "modelFound": model != nil,
            "solid": model?.isSolidLayer ?? false,
            "materialPath": model?.materialPath ?? "missing",
            "modelDeclaredSizeWH": model?.declaredSizeWH ?? [],
            "barDeclaredSizeWH": barModel?.declaredSizeWH ?? [],
            "materialCatalogPaths": catalog.materials.map(\.relativePath).sorted(),
            "shaderContractIdentities": catalog.shaderContracts.map(\.identity).sorted(),
            "tintScript": tint?.scriptSource ?? "missing",
            "numericValues": numericValues,
            "tintBindingKeys": tint?.bindingKeys ?? [],
            "tintRainbow": tint?.scriptProperties?["rainbow"]?.boolValue
                ?? false,
            "tintSpeed": tint?.scriptProperties?["speed"]?.numberValue
                ?? -1,
            "puppetNames": puppetModel?.puppetAttachments.map(\.name) ?? [],
            "puppetFrames": puppetModel?.puppetAttachments.map(\.modelBindFrameColumnMajor) ?? [],
            "renamedPuppetNames": renamedPuppetModel?.puppetAttachments.map(\.name) ?? [],
            "brokenPuppetModelRetained": brokenPuppetModel != nil,
            "brokenPuppetAttachments": brokenPuppetModel?.puppetAttachments.count ?? -1,
            "modelCatalogPaths": catalog.models.map(\.relativePath),
            "effectCatalogPaths": catalog.effectDefinitions.map(\.relativePath),
            "bytesReads": AssetReadProbe.calls,
            "particlesPreparedOnce": readsAfterCatalog == AssetReadProbe.calls
                && parsesAfterCatalog == ParticleParseProbe.calls && parsesAfterCatalog == 3
                && particleGraph.assetsByPath["particles/child.json"] != nil,
            "namespaceSurvivesBadDirectModel": dynamicAliases.first?.modelPath == "models/workshop/314/shared.json",
            "sharedComputedTemplateRemainsAvailable": selectedModels.contains("models/literal.json"),
            "selectedMaterialRoot": catalog.materials.first { $0.relativePath == "materials/shared.json" }?.passes.first?.shader ?? "",
        ]
        let normalCases = ["omitted", "null", "empty", "renamed", "valid", "missing",
                           "whitespace", "missing-color", "bad-material", "peer"]
        let normalRoots = normalCases.map { "particles/optional-normal/\($0).json" }
        var normalDefinitions: [String: SceneParticleAssetGraphLoader.PreparedDefinition] = [:]
        let normalCatalog = try SceneAssetCatalogLoader().load(resourceView: view,
            referencedResourcePaths: [], particlePaths: normalRoots,
            preparedParticleDefinition: { normalDefinitions[$0] = $1 })
        // These raw fixtures have no constants. Preserve the Catalog's typed slots
        // and material metadata; the production planners decide their meaning.
        let normalPasses = normalCatalog.materials.flatMap { material in
            material.passes.enumerated().map { index, pass in
                SceneParticleMaterialPass(materialPath: material.relativePath, passIndex: index,
                    shaderPath: pass.shader, texturePaths: pass.textures, textureSlots: pass.textureSlots,
                    blending: pass.blending, combos: pass.combos,
                    hasUserTextureInputs: !pass.userTextureInputs.isEmpty,
                    hasUserShaderValues: !pass.userShaderValues.isEmpty,
                    depthTest: pass.depthTest, depthWrite: pass.depthWrite,
                    cullMode: pass.cullMode, alphaWriting: pass.alphaWriting)
            }
        }
        let normalReads = AssetReadProbe.calls
        let normalParses = ParticleParseProbe.calls
        let normalGraph = try SceneParticleAssetGraphLoader(resourceView: view, stockTextureBundleURL: nil)
            .load(rootPaths: normalRoots, materialPasses: normalPasses, preparedDefinitions: normalDefinitions)
        var normalRows: [String: Any] = [:]
        for (name, path) in zip(normalCases, normalRoots) {
            let asset = normalGraph.assetsByPath[path]
            let pass = asset?.materialPass
            let plan = pass.flatMap { pass in
                SceneMaterialRenderState.compile(blending: pass.blending, depthTest: pass.depthTest,
                    depthWrite: pass.depthWrite, cullMode: pass.cullMode, alphaWriting: pass.alphaWriting,
                    missingBlending: .translucent).flatMap {
                        SceneParticleRefractionPlanner.plan(for: pass, renderState: $0)
                    }
            }
            let row: [String: Any] = [
                "asset": asset != nil, "slots": pass?.textureSlots.map { $0 as Any? ?? NSNull() } ?? [],
                "textures": pass?.texturePaths ?? [], "plan": plan != nil,
                "normal": plan?.normalReference as Any? ?? NSNull(),
                "amount": plan?.amount as Any? ?? NSNull(),
                "overbright": plan?.overbright as Any? ?? NSNull(),
                "textureReady": asset?.textureSource != nil,
                "refractionReady": asset?.refraction != nil,
                "normalReady": asset?.refraction?.normalTextureSource != nil,
                "pipelineReady": asset?.pipelineState != nil,
                "diagnostics": normalGraph.diagnostics.filter { $0.assetPath == path }.map {
                    ["kind": $0.kind.rawValue, "detail": $0.detail ?? ""]
                },
            ]
            normalRows[name] = row
        }
        result["optionalNormalCases"] = normalRows
        result["optionalNormalDefinitionsReused"] = normalParses == ParticleParseProbe.calls
            && normalParses - parsesAfterCatalog == normalCases.count
        result["optionalNormalDefinitionReadsReused"] = normalReads == AssetReadProbe.calls
        let roleReadsBefore = AssetReadProbe.calls
        let roleCatalog = try SceneAssetCatalogLoader().load(resourceView: view,
            referencedResourcePaths: ["xaterials/late.json", "xaterials/generic-only.json",
                "models/role-bridge.json", "models/role-no-suffix.json", "effects/role/effect.json",
                "xaterials/coat.json", "materials/role-hint.json"],
            additionalMaterialPaths: ["XATERIALS/coat.json", "xaterials/coat.json",
                "relocated/Surface Ω", "relocated/SURFACE Ω", "xaterials/broken.payload",
                "xaterials/missing.json", "MATERIALS/role-hint.json"],
            particlePaths: ["particles/role.json"])
        result["roleMaterialPaths"] = roleCatalog.materials.map(\.relativePath)
        result["roleMaterials"] = Dictionary(uniqueKeysWithValues: roleCatalog.materials.map { material in
            (material.relativePath, ["alpha": material.passes.first?.constantShaderValues["alpha"]?.components ?? [],
                "textures": material.passes.first?.textureSlots.map { $0 ?? "" } ?? []] as [String: Any])
        })
        result["roleReads"] = Dictionary(uniqueKeysWithValues: AssetReadProbe.calls.map {
            ($0.key, $0.value - (roleReadsBefore[$0.key] ?? 0))
        })
        let effectReadsBefore = AssetReadProbe.calls
        let effectParsesBefore = CatalogRoleParseProbe.effects
        let materialParsesBefore = CatalogRoleParseProbe.materials
        let explicitEffects = ["effects/explicit-role/effect.json", "relocated/Phase Ω.data",
            "relocated/NoSuffix", "Renamed/UPPER.JSON", "RENAMED/upper.json",
            "relocated-caps/EFFECT.JSON", "models/looks-effect.json", "xffects/pending.json",
            "xffects/broken.payload", "xffects/missing.json", "effects/dual-pending/effect.json"]
        let effectReferences = ["effects/dual-processed/effect.json", "models/effect-role-bridge.json",
            "models/effect-role-peer.json", "effects/dual-pending/effect.json"]
            + explicitEffects + ["xffects/generic-only.json"]
        let effectCatalog = try SceneAssetCatalogLoader().load(resourceView: view,
            referencedResourcePaths: effectReferences,
            additionalMaterialPaths: ["effects/dual-pending/effect.json"],
            effectPaths: explicitEffects)
        result["effectRoleInputs"] = explicitEffects; result["effectRoleReferences"] = effectReferences
        result["effectRoleDefinitions"] = effectCatalog.effectDefinitions.map(\.relativePath)
        result["effectRoleModels"] = effectCatalog.models.map(\.relativePath)
        result["effectRoleMaterials"] = effectCatalog.materials.map(\.relativePath)
        result["effectRoleMaterialAlpha"] = effectCatalog.materials.first {
            $0.relativePath == "xaterials/effect-role-material.json"
        }?.passes.first?.constantShaderValues["alpha"]?.components ?? []
        result["effectRoleReads"] = Dictionary(uniqueKeysWithValues: AssetReadProbe.calls.map {
            ($0.key, $0.value - (effectReadsBefore[$0.key] ?? 0))
        })
        result["effectRoleParses"] = Dictionary(uniqueKeysWithValues: CatalogRoleParseProbe.effects.map {
            ($0.key, $0.value - (effectParsesBefore[$0.key] ?? 0))
        })
        result["effectMaterialParses"] = Dictionary(uniqueKeysWithValues: CatalogRoleParseProbe.materials.map {
            ($0.key, $0.value - (materialParsesBefore[$0.key] ?? 0))
        })
        let cancelReads = AssetReadProbe.calls
        var cancelled = false
        do {
            _ = try SceneAssetCatalogLoader().load(resourceView: view,
                referencedResourcePaths: effectReferences,
                checkCancellation: { throw CatalogFixtureCancellation.requested })
        } catch CatalogFixtureCancellation.requested { cancelled = true }
        result["effectRoleCancellationPropagated"] = cancelled
        result["effectRoleCancellationDidNotRead"] = cancelReads == AssetReadProbe.calls
        let conflictReadsBefore = AssetReadProbe.calls
        let conflictEffectsBefore = CatalogRoleParseProbe.effects
        let conflictMaterialsBefore = CatalogRoleParseProbe.materials
        let conflictEffects = ["materials/explicit-effect-conflict.json"]
        let conflictMaterial = "effects/explicit-material-conflict/effect.json"
        let conflictCatalog = try SceneAssetCatalogLoader().load(resourceView: view,
            referencedResourcePaths: conflictEffects + [conflictMaterial],
            additionalMaterialPaths: [conflictMaterial],
            effectPaths: conflictEffects)
        result["hintConflictDefinitions"] = conflictCatalog.effectDefinitions.map(\.relativePath)
        result["hintConflictMaterials"] = conflictCatalog.materials.map(\.relativePath)
        for (key, values, before) in [
            ("hintConflictReads", AssetReadProbe.calls, conflictReadsBefore),
            ("hintConflictEffects", CatalogRoleParseProbe.effects, conflictEffectsBefore),
            ("hintConflictMaterialParses", CatalogRoleParseProbe.materials, conflictMaterialsBefore)] {
            result[key] = Dictionary(uniqueKeysWithValues: values.map {
                ($0.key, $0.value - (before[$0.key] ?? 0))
            })
        }
        let imageReadsBefore = AssetReadProbe.calls
        let imageModelsBefore = CatalogRoleParseProbe.models
        let imageMaterialsBefore = CatalogRoleParseProbe.materials
        let imageEffectsBefore = CatalogRoleParseProbe.effects
        let imageReferencesBefore = ModelReferenceProbe.resolved.count
        let explicitImages = ["providers/scene Ω.payload", "providers/NoSuffix", "providers/UPPER.JSON",
            "PROVIDERS/upper.json", "materials/image-role.json", "effects/image-role/effect.json",
            "models/image-pending.json", "models/image-processed.json", "models/role-bridge.json",
            "providers/broken.payload", "providers/missing.json"]
        let imageReferences = ["models/image-pending.json", "models/image-processed.json"]
            + explicitImages + ["effects/image-promoter/effect.json", "xffects/generic-only.json"]
        let imageCatalog = try SceneAssetCatalogLoader().load(resourceView: view,
            referencedResourcePaths: imageReferences,
            scriptSources: ["thisScene.createLayer('providers/scene Ω.payload'); thisScene.createLayer('models/image-processed.json');"],
            additionalMaterialPaths: ["models/image-pending.json"],
            imageModelPaths: explicitImages)
        result["imageRoleInputs"] = explicitImages; result["imageRoleReferences"] = imageReferences
        result["imageRoleModels"] = Dictionary(uniqueKeysWithValues: imageCatalog.models.map {
            ($0.relativePath, ["material": $0.materialPath ?? "", "size": $0.declaredSizeWH ?? []] as [String: Any])
        })
        result["imageRoleMaterials"] = imageCatalog.materials.map(\.relativePath)
        result["imageRoleEffects"] = imageCatalog.effectDefinitions.map(\.relativePath)
        result["imageRoleResolved"] = Array(ModelReferenceProbe.resolved.dropFirst(imageReferencesBefore))
        for (key, values, before) in [
            ("imageRoleReads", AssetReadProbe.calls, imageReadsBefore),
            ("imageRoleModelParses", CatalogRoleParseProbe.models, imageModelsBefore),
            ("imageRoleMaterialParses", CatalogRoleParseProbe.materials, imageMaterialsBefore),
            ("imageRoleEffectParses", CatalogRoleParseProbe.effects, imageEffectsBefore)] {
            result[key] = Dictionary(uniqueKeysWithValues: values.map {
                ($0.key, $0.value - (before[$0.key] ?? 0))
            })
        }
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class SceneAssetCatalogResourceViewTests(unittest.TestCase):
    EFFECT_ROLE_DEFINITIONS = {
        "effects/explicit-role/effect.json", "relocated/Phase Ω.data", "relocated/NoSuffix",
        "Renamed/UPPER.JSON", "relocated-caps/EFFECT.JSON", "models/looks-effect.json",
        "xffects/pending.json", "effects/dual-pending/effect.json", "effects/dual-processed/effect.json",
    }

    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = None
        if evidence := os.environ.get("MWX_SCENE_CATALOG_EVIDENCE"):
            Path(evidence).mkdir(parents=True, exist_ok=True)
            root = Path(tempfile.mkdtemp(prefix="catalog-resource-view-", dir=evidence))
        else:
            cls.temporary_directory = tempfile.TemporaryDirectory(prefix="mwx-scene-catalog-resource-view-")
            root = Path(cls.temporary_directory.name)
        project = root / "project"
        package = root / "package"
        stock = root / "stock-assets"
        project.mkdir()
        package.mkdir()
        (project / "project.json").write_text(
            json.dumps({"type": "scene", "file": "scene.json"}),
            encoding="utf-8",
        )
        (project / "scene.json").write_text("{}", encoding="utf-8")

        package_model = package / "models/workshop/bar.json"
        package_material = package / "materials/workshop/bar.json"
        package_vertex = package / "shaders/workshop/tint.vert"
        package_fragment = package / "shaders/workshop/tint.frag"
        for path in (
            package_model,
            package_material,
            package_vertex,
            package_fragment,
        ):
            path.parent.mkdir(parents=True, exist_ok=True)
        package_model.write_text(
            json.dumps({
                "material": "materials/workshop/bar.json",
                "width": 1920,
                "height": 1080,
            }),
            encoding="utf-8",
        )
        package_material.write_text(
            json.dumps({
                "passes": [{
                    "shader": "workshop/tint",
                    "constantshadervalues": {
                        **{name: case[0] for name, case in SHADER_VALUE_NUMERIC_CASES.items()},
                        **SHADER_VALUE_NESTED_CASES,
                        "g_TintColor": {
                            "value": "1 1 1",
                            "script": "export function update(value) { return value; }",
                            "scriptproperties": {
                                "rainbow": True,
                                "speed": 0.5,
                            },
                        },
                    },
                }],
            }),
            encoding="utf-8",
        )
        package_vertex.write_text("void main() {}", encoding="utf-8")
        package_fragment.write_text("void main() {}", encoding="utf-8")

        # A loose model's puppet reference follows the global namespace: the
        # package's same-path MDL wins. Both parsers below are production code.
        (project / "models").mkdir()
        for name, puppet in (("puppet-owner", "models/rig.mdl"),
                             ("broken-puppet-owner", "models/broken.mdl"),
                             ("renamed-owner", "models/renamed-rig.mdl")):
            (project / f"models/{name}.json").write_text(json.dumps({"puppet": puppet}))
        (package / "models/rig.mdl").write_bytes(build_attachment_mdl())
        (project / "models/rig.mdl").write_bytes(build_attachment_mdl(
            attachment_names=("wrong-lower-root", "wrong-peer")))
        (package / "models/renamed-rig.mdl").write_bytes(build_attachment_mdl(
            attachment_names=("renamed-socket", "renamed-peer")))
        (project / "models/broken.mdl").write_bytes(b"MDLV0023\0MDAT0001")
        (project / "models/invalid.json").write_text("[not JSON")
        (package / "materials/invalid.json").write_text("[not JSON")
        for name, contents in (("valid", {"passes": [{"material": "effects-only"}],
                                        "dependencies": ["effects/linked/effect.json"]}),
                               ("invalid", None)):
            effect = package / f"effects/{name}/effect.json"
            effect.parent.mkdir(parents=True)
            effect.write_text(json.dumps(contents) if contents else "[not JSON")

        def author(relative, payload, folder=package):
            path = folder / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(json.dumps(payload) if not isinstance(payload, str) else payload)

        author("effects/linked/effect.json", {"passes": [{"material": "materials/linked-only.json"}]})
        author("materials/linked-only.json", {"passes": [{"shader": "effect-only"}]})

        author("models/shared.json", "{bad direct")
        author("models/shared.json", {"material": "materials/wrong-lower.json"}, project)
        author("models/workshop/314/shared.json", {"material": "materials/shared.json"})
        author("models/literal.json", {"material": "materials/literal.json"})
        author("materials/literal.json", {"passes": [{"constantshadervalues": {
            "alpha": {"value": 1, "script": "export function update() { thisScene.createLayer('models/material-created.json'); return 1; }"}}}]})
        author("models/material-created.json", {"material": "materials/final.json"})
        for name in ("shared", "final", "particle-root", "particle-child"):
            author(f"materials/{name}.json", {"passes": [{"shader": "genericparticle"}]})
        author("materials/shared.json", {"passes": [{"shader": "wrong-lower"}]}, project)
        author("models/exact-material.json", {"material": "must-not-guess"})
        author("materials/must-not-guess.json", {"passes": [{"shader": "spurious"}]})
        author("Particles/Root.JSON", {"material": "materials/particle-root.json",
            "emitter": [{"name": "boxRandom"}], "children": [{"name": "particles/child.json"}]})
        author("particles/child.json", {"material": "materials/particle-child.json",
            "emitter": [{"name": "boxRandom"}], "children": [{"name": "Particles/Root.JSON"}]})
        author("particles/hidden.json", "{bad hidden")
        role_material = {"passes": [{"shader": "flat", "textures": ["materials/role-color.png"],
                                     "constantshadervalues": {"alpha": .375}}]}
        for path in ["xaterials/coat.json", "xaterials/late.json", "relocated/Surface Ω",
                     "xaterials/model-surface.data", "xaterials/effect-surface", "xaterials/particle-surface.bin",
                     "materials/role-hint.json", "xaterials/generic-only.json",
                     "xaterials/dependency-only.json", "xaterials/unreferenced.json"]:
            author(path, role_material)
        author("xaterials/unreferenced-bad.json", "[not JSON")
        author("xaterials/broken.payload", "[not JSON")
        author("xaterials/coat.json", {"passes": [{"shader": "wrong-lower",
               "constantshadervalues": {"alpha": .125}}]}, project)
        author("models/role-bridge.json", {"material": "xaterials/late.json"})
        author("models/role-no-suffix.json", {"material": "xaterials/model-surface.data"})
        author("effects/role/effect.json", {"passes": [{"material": "xaterials/effect-surface"}],
                                          "dependencies": ["xaterials/dependency-only.json"]})
        author("particles/role.json", {"material": "xaterials/particle-surface.bin",
                                      "emitter": [{"name": "boxRandom"}]})
        effect_role = {"passes": [{"material": "xaterials/effect-role-material.json"}],
                       "dependencies": ["xffects/dependency-only.json"]}
        for path in ["effects/explicit-role/effect.json", "relocated/Phase Ω.data", "relocated/NoSuffix",
                     "Renamed/UPPER.JSON", "relocated-caps/EFFECT.JSON", "models/looks-effect.json",
                     "xffects/pending.json", "xffects/generic-only.json", "xffects/dependency-only.json",
                     "xffects/unreferenced.json"]:
            author(path, effect_role)
        author("xffects/unreferenced-bad.json", "[not JSON")
        author("xffects/broken.payload", "[not JSON")
        author("xaterials/effect-role-material.json", {"passes": [{"shader": "flat",
               "constantshadervalues": {"alpha": .625}}]})
        author("effects/explicit-role/effect.json", {"passes": [{"material": "xaterials/wrong-effect-role.json"}]}, project)
        author("xaterials/wrong-effect-role.json", {"passes": [{"shader": "flat"}]})
        dual_role = {"passes": [{"shader": "flat", "textures": ["materials/role-color.png"]}]}
        for path in ["effects/dual-processed/effect.json", "effects/dual-pending/effect.json"]:
            author(path, dual_role)
        for path in ["models/effect-role-bridge.json", "models/effect-role-peer.json"]:
            author(path, {"material": "effects/dual-processed/effect.json"})
        author("materials/explicit-effect-conflict.json", {"passes": []})
        author("effects/explicit-material-conflict/effect.json", {"passes": [{"shader": "flat"}]})
        image_model = {"material": "xaterials/effect-role-material.json", "width": 320, "height": 180}
        for path in ["providers/scene Ω.payload", "providers/NoSuffix", "providers/UPPER.JSON",
                     "materials/image-role.json", "effects/image-role/effect.json"]:
            author(path, image_model)
        for path in ["models/image-pending.json", "models/image-processed.json"]:
            author(path, {**image_model, "passes": [{"shader": "flat"}]})
        author("providers/broken.payload", "[not JSON")
        author("effects/image-promoter/effect.json", {"passes": [{"material": "models/image-processed.json"}]})
        color = "optional-normal/color"
        normal = "optional-normal/normal"
        normal_slots = {
            "omitted": [color], "null": [color, None], "empty": [color, ""],
            "renamed": ["relocated/renamed-color", None], "valid": [color, normal],
            "missing": [color, "optional-normal/absent"], "whitespace": [color, "   "],
            "missing-color": ["optional-normal/absent-color", None],
            "bad-material": [color, None], "peer": [color],
        }
        for name, slots in normal_slots.items():
            material = f"materials/optional-normal/{name}.json"
            author(f"particles/optional-normal/{name}.json", {
                "material": material, "emitter": [{"name": "sphereRandom"}],
                "renderer": [{"name": "sprite"}],
            })
            author(material, "{invalid material" if name == "bad-material" else {"passes": [{
                "shader": "relocated/genericparticle" if name == "renamed" else "genericparticle",
                "textures": slots, "combos": {} if name == "peer" else {"REFRACT": 1},
                "blending": "translucent", "depthtest": "disabled", "depthwrite": "disabled",
                "cullmode": "nocull",
            }]})
        # AssetGraph resolves resource identity; decoding/upload belongs to the
        # existing refraction pixel gate. Use actual PNG bytes for these leaves.
        png = base64.b64decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR4nGP4DwQACfsD/fteaysAAAAASUVORK5CYII=")
        for relative in (color, normal, "relocated/renamed-color"):
            path = package / f"materials/{relative}.png"
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(png)
        for relative, payload in (
            ("models/unreferenced.json", {"material": "materials/unreferenced.json"}),
            ("models/unreferenced-invalid.json", "{bad unused"),
            ("models/only-computed.json", {"material": "materials/unreferenced.json"}),
            ("materials/unreferenced.json", {"passes": [{"shader": "unused-author"}]}),
            ("materials/unreferenced-invalid.json", "{bad unused"),
            ("effects/unreferenced/effect.json", {"passes": [{"material": "unreferenced"}]}),
            ("shaders/unused-author.vert", "unused"), ("shaders/unused-author.frag", "unused"),
            ("materials/wrong-lower.json", {"passes": [{"shader": "spurious"}]})):
            author(relative, payload)

        stock_model = stock / "models/util/solidlayer_depthtest.json"
        stock_material = stock / "materials/util/solidlayer_depthtest.json"
        stock_vertex = stock / "shaders/flat.vert"
        stock_fragment = stock / "shaders/flat.frag"
        for path in (stock_model, stock_material, stock_vertex, stock_fragment):
            path.parent.mkdir(parents=True, exist_ok=True)
        stock_model.write_text(
            json.dumps({
                "material": "materials/util/solidlayer_depthtest.json",
                "solidlayer": True,
            }),
            encoding="utf-8",
        )
        stock_material.write_text(
            json.dumps({"passes": [{"shader": "flat", "blending": "translucent"}]}),
            encoding="utf-8",
        )
        stock_vertex.write_text("void main() {}", encoding="utf-8")
        stock_fragment.write_text("void main() {}", encoding="utf-8")
        (stock / "materials/effects-only.json").write_text(json.dumps({
            "passes": [{"shader": "effect-only"}]}))
        for suffix in ("vert", "frag"):
            (stock / f"shaders/effect-only.{suffix}").write_text("void main() {}")
        unused = stock / "materials/unreferenced/spurious.json"
        unused.parent.mkdir(parents=True)
        unused.write_text(json.dumps({"passes": [{"shader": "spurious"}]}))
        for suffix in ("vert", "frag"):
            (stock / f"shaders/spurious.{suffix}").write_text("void main() {}")

        catalog_source = Path(os.environ.get("MWX_SCENE_CATALOG_SOURCE",
                              SCENE_ROOT / "Resources/Assets/SceneAssetCatalog.swift")).resolve()
        catalog_text = catalog_source.read_text()
        supports_effect_role = "effectPaths: [String]" in catalog_text
        supports_image_role = "imageModelPaths: [String]" in catalog_text
        harness = root / "Harness.swift"
        harness_text = HARNESS if supports_effect_role else HARNESS.replace(
            ",\n            effectPaths: explicitEffects", "").replace(
            ",\n            effectPaths: conflictEffects", "")
        if not supports_image_role:
            harness_text = harness_text.replace(",\n            imageModelPaths: explicitImages", "")
        harness.write_text(harness_text, encoding="utf-8")
        view_source = SHADER_CONTRACT_RESOURCE_RESOLUTION_SOURCES["SceneResourceView.swift"]
        counted_view = root / "SceneResourceView.swift"
        original_read = """        ) throws -> Data {
            try owner.readBytes(self, maximumBytes: maximumBytes, within: directory,"""
        counted_view.write_text(view_source.read_text().replace(original_read,
            """        ) throws -> Data {
            AssetReadProbe.calls[relativePath, default: 0] += 1
            return try owner.readBytes(self, maximumBytes: maximumBytes, within: directory,""", 1))
        parser_source = SCENE_ROOT / "Systems/Particles/SceneParticleDefinitionParser.swift"
        counted_parser = root / parser_source.name
        counted_parser.write_text(parser_source.read_text().replace(
            "func parse(data: Data) throws -> SceneParticleDefinition {",
            "func parse(data: Data) throws -> SceneParticleDefinition {\n        ParticleParseProbe.calls += 1", 1))
        sources = [counted_view if path == view_source else counted_parser if path == parser_source else path
                   for path in SWIFT_SOURCES]
        dynamic_source = SCENE_ROOT / "Systems/Script/SceneScriptDynamicImageReferenceAnalysis.swift"
        counted_dynamic = root / dynamic_source.name
        dynamic_text = dynamic_source.read_text()
        assert dynamic_text.count("        return references\n") == 1
        counted_dynamic.write_text(dynamic_text.replace("        return references\n",
            "        ModelReferenceProbe.resolved += references.map(\\.modelPath)\n        return references\n", 1))
        sources = [counted_dynamic if path == dynamic_source else path for path in sources]
        counted_catalog = root / "SceneAssetCatalog.swift"
        for marker, field in [(") throws -> SceneAssetCatalog.ModelAsset? {", "models"),
                              (") throws -> SceneAssetCatalog.MaterialAsset? {", "materials"),
                              ("""    nonisolated private func loadEffectDefinition(
        _ resource: SceneResourceView.Handle,
        checkCancellation: (() throws -> Void)?
    ) throws -> (definition: SceneEffectDefinition?, diagnostic: SceneEffectDefinitionDiagnostic?) {""", "effects")]:
            assert catalog_text.count(marker) == 1
            catalog_text = catalog_text.replace(marker, marker +
                f"\n        CatalogRoleParseProbe.{field}[resource.relativePath, default: 0] += 1", 1)
        counted_catalog.write_text(catalog_text)
        sources = [counted_catalog if path.name == "SceneAssetCatalog.swift" else path for path in sources]
        (root / "catalog-api-adaptation.json").write_text(json.dumps({
            "catalogSource": str(catalog_source), "supportsEffectRole": supports_effect_role,
            "supportsImageRole": supports_image_role,
            "oldAdaptation": "Only omit unsupported role labels; referencedResourcePaths already contains the same explicit paths in both versions.",
            "scope": "Parser-entry counters observe the original loaders; dual role means two schema invocations and two readBytes calls, not one global JSON parse.",
        }, indent=2))
        cls.binary = root / "scene-catalog-resource-view-harness"
        command = [
                "xcrun", "--sdk", "macosx", "swiftc",
                *(str(path) for path in sources),
                str(harness), "-o", str(cls.binary),
            ]
        (root / "compile-command.json").write_text(json.dumps(command, indent=2))
        compiled = subprocess.run(
            command,
            cwd=REPOSITORY_ROOT,
            capture_output=True,
            text=True,
        )
        (root / "compile.stdout").write_text(compiled.stdout)
        (root / "compile.stderr").write_text(compiled.stderr)
        if compiled.returncode:
            raise RuntimeError(compiled.stdout + compiled.stderr)
        completed = subprocess.run(
            [str(cls.binary), str(project), str(package), str(stock)],
            cwd=REPOSITORY_ROOT,
            capture_output=True,
            text=True,
        )
        (root / "run.stdout").write_text(completed.stdout)
        (root / "run.stderr").write_text(completed.stderr)
        if completed.returncode:
            raise RuntimeError(completed.stdout + completed.stderr)
        cls.result = json.loads(completed.stdout)
        (root / "result.json").write_text(json.dumps(cls.result, indent=2))

    @classmethod
    def tearDownClass(cls) -> None:
        if cls.temporary_directory is not None:
            cls.temporary_directory.cleanup()

    def test_explicit_material_roles_survive_directory_suffix_alias_and_root_selection(self) -> None:
        expected = {"xaterials/coat.json", "xaterials/late.json", "relocated/Surface Ω",
                    "xaterials/model-surface.data", "xaterials/effect-surface", "xaterials/particle-surface.bin",
                    "materials/role-hint.json"}
        self.assertEqual(set(self.result["roleMaterialPaths"]), expected)
        self.assertEqual(len(self.result["roleMaterialPaths"]), len(expected))
        for path in expected:
            with self.subTest(material=path):
                self.assertEqual(self.result["roleMaterials"][path],
                                 {"alpha": [.375], "textures": ["materials/role-color.png"]})

    def test_explicit_image_models_preserve_metadata_material_closure_and_dynamic_names(self):
        paths = {"providers/scene Ω.payload", "providers/NoSuffix", "providers/UPPER.JSON",
                 "materials/image-role.json", "effects/image-role/effect.json",
                 "models/image-pending.json", "models/image-processed.json", "models/role-bridge.json"}
        self.assertEqual(set(self.result["imageRoleModels"]), paths)
        for path in paths - {"models/role-bridge.json"}:
            with self.subTest(image_model=path):
                self.assertEqual(self.result["imageRoleModels"][path],
                                 {"material": "xaterials/effect-role-material.json", "size": [320, 180]})
        self.assertEqual(set(self.result["imageRoleMaterials"]), {
            "xaterials/effect-role-material.json", "xaterials/late.json",
            "models/image-pending.json", "models/image-processed.json"})
        self.assertEqual(self.result["imageRoleEffects"], ["effects/image-promoter/effect.json"])
        self.assertEqual(self.result["imageRoleResolved"],
                         ["providers/scene Ω.payload", "models/image-processed.json"])

    def test_image_model_roles_parse_only_real_consumers_and_keep_bad_inputs_local(self):
        duals = {"models/image-pending.json", "models/image-processed.json"}
        pure = {"providers/scene Ω.payload", "providers/NoSuffix", "providers/UPPER.JSON",
                "materials/image-role.json", "effects/image-role/effect.json", "models/role-bridge.json"}
        for path in pure | duals | {"providers/broken.payload"}:
            with self.subTest(image_role=path):
                self.assertEqual(self.result["imageRoleModelParses"].get(path, 0), 1)
                self.assertEqual(self.result["imageRoleReads"].get(path, 0), 2 if path in duals else 1)
                self.assertEqual(self.result["imageRoleMaterialParses"].get(path, 0), int(path in duals))
                self.assertEqual(self.result["imageRoleEffectParses"].get(path, 0), 0)
        for path in ["providers/missing.json", "xffects/generic-only.json", "xffects/unreferenced.json"]:
            with self.subTest(unused_image=path):
                self.assertEqual(self.result["imageRoleReads"].get(path, 0), 0)
                self.assertEqual(self.result["imageRoleModelParses"].get(path, 0), 0)
        self.assertNotIn("providers/broken.payload", self.result["imageRoleModels"])
        self.assertNotIn("providers/missing.json", self.result["imageRoleModels"])
        for path in ["xaterials/effect-role-material.json", "xaterials/late.json"]:
            self.assertEqual(self.result["imageRoleMaterialParses"].get(path, 0), 1)
            self.assertEqual(self.result["imageRoleReads"].get(path, 0), 1)

    def test_explicit_effect_roles_keep_actual_paths_and_skip_model_hints(self):
        paths = self.result["effectRoleDefinitions"]
        self.assertEqual(set(paths), self.EFFECT_ROLE_DEFINITIONS)
        self.assertEqual(len(paths), len(self.EFFECT_ROLE_DEFINITIONS))
        self.assertNotIn("models/looks-effect.json", self.result["effectRoleModels"])
        self.assertEqual(set(self.result["effectRoleMaterials"]), {
            "xaterials/effect-role-material.json", "effects/dual-pending/effect.json",
            "effects/dual-processed/effect.json"})
        self.assertEqual(self.result["effectRoleMaterialAlpha"], [.625])

    def test_pending_and_processed_effect_promotions_parse_only_added_roles(self):
        def counts(key):
            values = {}
            for path, count in self.result[key].items():
                values[path.casefold()] = values.get(path.casefold(), 0) + count
            return values
        reads, effects, materials = [counts(key) for key in
            ("effectRoleReads", "effectRoleParses", "effectMaterialParses")]
        duals = {"effects/dual-pending/effect.json", "effects/dual-processed/effect.json"}
        for path in self.EFFECT_ROLE_DEFINITIONS | {"xffects/broken.payload"}:
            with self.subTest(effect=path):
                self.assertEqual(effects.get(path.casefold(), 0), 1)
                self.assertEqual(reads.get(path.casefold(), 0), 2 if path in duals else 1)
        for path in duals | {"xaterials/effect-role-material.json"}:
            with self.subTest(material=path):
                self.assertEqual(materials.get(path, 0), 1)
        self.assertEqual(reads.get("xaterials/effect-role-material.json", 0), 1)
        for path in ["models/effect-role-bridge.json", "models/effect-role-peer.json"]:
            self.assertEqual(reads.get(path, 0), 1)
        for path, effect, material in [
            ("materials/explicit-effect-conflict.json", 1, 0),
            ("effects/explicit-material-conflict/effect.json", 0, 1),
        ]:
            with self.subTest(explicit_role_over_hint=path):
                self.assertEqual(self.result["hintConflictReads"].get(path, 0), 1)
                self.assertEqual(self.result["hintConflictEffects"].get(path, 0), effect)
                self.assertEqual(self.result["hintConflictMaterialParses"].get(path, 0), material)
                self.assertEqual(path in self.result["hintConflictDefinitions"], bool(effect))
                self.assertEqual(path in self.result["hintConflictMaterials"], bool(material))

    def test_effect_role_failures_and_cancellation_preserve_healthy_peers(self):
        paths = self.result["effectRoleDefinitions"]
        self.assertNotIn("xffects/broken.payload", paths)
        self.assertNotIn("xffects/missing.json", paths)
        self.assertIn("effects/explicit-role/effect.json", paths)
        reads = self.result["effectRoleReads"]
        for path in ["xffects/generic-only.json", "xffects/dependency-only.json", "xffects/missing.json",
                     "xffects/unreferenced.json", "xffects/unreferenced-bad.json", "xaterials/wrong-effect-role.json"]:
            with self.subTest(unused=path):
                self.assertEqual(sum(count for name, count in reads.items() if name.casefold()==path.casefold()), 0)
        self.assertTrue(self.result["effectRoleCancellationPropagated"])
        self.assertTrue(self.result["effectRoleCancellationDidNotRead"])

    def test_pending_and_processed_role_promotions_read_materials_once(self) -> None:
        reads = {}
        for path, count in self.result["roleReads"].items():
            reads[path.casefold()] = reads.get(path.casefold(), 0) + count
        for path in ["xaterials/coat.json", "xaterials/late.json", "relocated/surface ω",
                     "xaterials/model-surface.data", "xaterials/effect-surface", "xaterials/particle-surface.bin",
                     "materials/role-hint.json", "models/role-bridge.json", "models/role-no-suffix.json",
                     "particles/role.json", "xaterials/broken.payload"]:
            with self.subTest(material=path):
                self.assertEqual(reads.get(path, 0), 1, self.result["roleReads"])
        for path in ["xaterials/generic-only.json", "xaterials/dependency-only.json",
                     "xaterials/unreferenced.json", "xaterials/unreferenced-bad.json", "xaterials/missing.json"]:
            with self.subTest(unknown=path):
                self.assertEqual(reads.get(path, 0), 0, self.result["roleReads"])
        self.assertNotIn("xaterials/broken.payload", self.result["roleMaterialPaths"])

    def test_referenced_stock_solid_model_restores_type_without_global_catalog_churn(self) -> None:
        self.assertTrue(self.result["modelFound"])
        self.assertTrue(self.result["solid"])
        self.assertEqual(
            self.result["materialPath"],
            "materials/util/solidlayer_depthtest.json",
        )
        self.assertEqual(self.result["materialCatalogPaths"], [
            "materials/effects-only.json", "materials/final.json", "materials/linked-only.json", "materials/literal.json",
            "materials/particle-child.json", "materials/particle-root.json", "materials/shared.json",
            "materials/util/solidlayer_depthtest.json",
            "materials/workshop/bar.json"])
        self.assertTrue({"effect-only", "flat", "workshop/tint"}.issubset(self.result["shaderContractIdentities"]))

    def test_model_declared_size_parses_from_scalar_width_height(self) -> None:
        # bar.json declares scalar width/height → the model asset carries the
        # design size; a model without them (solidlayer_depthtest) carries none.
        self.assertEqual(self.result["barDeclaredSizeWH"], [1920.0, 1080.0])
        self.assertEqual(self.result["modelDeclaredSizeWH"], [])

    def test_material_constant_preserves_script_shape_and_properties(self) -> None:
        self.assertEqual(
            self.result["tintScript"],
            "export function update(value) { return value; }",
        )
        self.assertEqual(
            self.result["tintBindingKeys"],
            ["script", "scriptproperties", "value"],
        )
        self.assertTrue(self.result["tintRainbow"])
        self.assertEqual(self.result["tintSpeed"], 0.5)

    def test_numeric_arrays_preserve_full_values_without_adding_material_timelines(self):
        values = self.result["numericValues"]
        assert_numeric_shader_values(self, values)
        self.assertEqual(values["wrappedVector"]["userValueKind"], "null")
        self.assertEqual(values["scriptArray"]["bindingKeys"], ["script", "scriptproperties", "value"])
        self.assertIn("update", values["scriptArray"]["script"])
        self.assertEqual(values["scriptArray"]["speed"], 0.5)
        self.assertFalse(values["timelineArray"]["hasTimeline"])
        for name in SHADER_VALUE_NESTED_CASES:
            self.assertFalse(values[name]["hasComponents"], name)

    def test_real_attachment_reader_keeps_global_source_and_renamed_records(self) -> None:
        self.assertEqual(self.result["puppetNames"], ["hand", "orb"])
        self.assertEqual(self.result["renamedPuppetNames"], ["renamed-socket", "renamed-peer"])
        self.assertEqual([frame[12:14] for frame in self.result["puppetFrames"]],
                         [[-75.0, -13.0], [-100.0, -50.0]])

    def test_ordinary_bad_attachment_keeps_its_model_and_valid_peers(self) -> None:
        self.assertTrue(self.result["brokenPuppetModelRetained"])
        self.assertEqual(self.result["brokenPuppetAttachments"], 0)
        self.assertEqual(self.result["puppetNames"], ["hand", "orb"])

    def test_ordinary_invalid_json_is_local_to_each_catalog_entry(self) -> None:
        self.assertNotIn("models/invalid.json", self.result["modelCatalogPaths"])
        self.assertNotIn("materials/invalid.json", self.result["materialCatalogPaths"])
        self.assertEqual(self.result["effectCatalogPaths"], ["effects/linked/effect.json", "effects/valid/effect.json"])
        self.assertIn("models/puppet-owner.json", self.result["modelCatalogPaths"])

    def test_effect_reference_resolves_extensionless_material_from_global_namespace(self) -> None:
        self.assertIn("materials/effects-only.json", self.result["materialCatalogPaths"])
        self.assertIn("effect-only", self.result["shaderContractIdentities"])

    def test_reference_closure_reads_only_actual_consumers_and_parses_particles_once(self) -> None:
        # Root handles preserve the index's actual spelling. On a case-insensitive
        # volume, creating Particles first also gives later child files that
        # directory spelling. Sum aliases so duplicate reads still fail.
        reads: dict[str, int] = {}
        for path, count in self.result["bytesReads"].items():
            key = path.casefold()
            reads[key] = reads.get(key, 0) + count
        for path in ("models/unreferenced.json", "models/unreferenced-invalid.json",
                     "models/only-computed.json",
                     "materials/unreferenced.json", "materials/unreferenced-invalid.json",
                     "effects/unreferenced/effect.json", "shaders/unused-author.vert",
                     "shaders/unused-author.frag", "materials/must-not-guess.json",
                     "materials/wrong-lower.json"):
            with self.subTest(unused=path):
                self.assertEqual(reads.get(path.casefold(), 0), 0, self.result["bytesReads"])
        for path in ("models/shared.json", "models/workshop/314/shared.json", "models/literal.json",
                     "models/material-created.json", "Particles/Root.JSON", "particles/child.json"):
            with self.subTest(consumer=path):
                self.assertEqual(reads[path.casefold()], 1, self.result["bytesReads"])
        self.assertTrue(self.result["namespaceSurvivesBadDirectModel"])
        self.assertTrue(self.result["sharedComputedTemplateRemainsAvailable"])
        self.assertTrue(self.result["particlesPreparedOnce"])
        self.assertEqual(self.result["selectedMaterialRoot"], "genericparticle")
        self.assertEqual(reads["materials/shared.json"], 1)
        self.assertNotIn("models/shared.json", self.result["modelCatalogPaths"])
        self.assertIn("models/material-created.json", self.result["modelCatalogPaths"])
        self.assertIn("materials/particle-root.json", self.result["materialCatalogPaths"])
        self.assertIn("materials/particle-child.json", self.result["materialCatalogPaths"])

    def test_raw_optional_normal_slots_reach_the_real_planner_and_asset_graph(self) -> None:
        rows = self.result["optionalNormalCases"]
        color = "optional-normal/color"
        for name, slots in (("omitted", [color]), ("null", [color, None]),
                            ("empty", [color, None]), ("renamed", ["relocated/renamed-color", None])):
            with self.subTest(optional=name):
                row = rows[name]
                self.assertEqual(row["slots"], slots)
                self.assertEqual(row["textures"], [slots[0]])
                self.assertTrue(row["asset"] and row["plan"] and row["textureReady"])
                self.assertTrue(row["refractionReady"] and row["pipelineReady"])
                self.assertIsNone(row["normal"])
                self.assertFalse(row["normalReady"])
                self.assertAlmostEqual(row["amount"], 0.05, places=6)
                self.assertEqual(row["overbright"], 1)
                self.assertEqual(row["diagnostics"], [])
        valid = rows["valid"]
        self.assertEqual(valid["slots"], [color, "optional-normal/normal"])
        self.assertEqual(valid["normal"], "optional-normal/normal")
        self.assertTrue(valid["plan"] and valid["textureReady"] and valid["normalReady"])
        self.assertTrue(valid["refractionReady"] and valid["pipelineReady"])
        self.assertEqual(valid["diagnostics"], [])
        for name, reference in (("missing", "optional-normal/absent"), ("whitespace", "   ")):
            with self.subTest(explicit_normal=name):
                row = rows[name]
                self.assertTrue(row["plan"])
                self.assertEqual(row["slots"], [color, reference])
                self.assertEqual(row["normal"], reference)
                self.assertFalse(row["refractionReady"] or row["textureReady"])
                self.assertIn({"kind": "refractionUnsupported", "detail": "normalTextureUnavailable"},
                              row["diagnostics"])
        missing_color = rows["missing-color"]
        self.assertTrue(missing_color["plan"])
        self.assertFalse(missing_color["textureReady"])
        self.assertIn({"kind": "missingTextureFile", "detail": "optional-normal/absent-color"},
                      missing_color["diagnostics"])
        self.assertFalse(rows["bad-material"]["plan"] or rows["bad-material"]["textureReady"])
        self.assertIn("missingMaterial", [d["kind"] for d in rows["bad-material"]["diagnostics"]])
        peer = rows["peer"]
        self.assertTrue(peer["asset"] and peer["textureReady"] and peer["pipelineReady"])
        self.assertFalse(peer["refractionReady"])
        self.assertEqual(peer["diagnostics"], [])
        self.assertTrue(self.result["optionalNormalDefinitionsReused"])
        self.assertTrue(self.result["optionalNormalDefinitionReadsReused"])


if __name__ == "__main__":
    unittest.main()
