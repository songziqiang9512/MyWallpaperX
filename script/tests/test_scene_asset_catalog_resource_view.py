#!/usr/bin/env python3

from __future__ import annotations

import json
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
from script.tests.test_scene_puppet_mesh import build_attachment_mdl
from script.tests.test_scene_particle_assets import SWIFT_SOURCES as PARTICLE_GRAPH_SOURCES


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
        let puppetModel = catalog.models.first { $0.relativePath == "models/puppet-owner.json" }
        let brokenPuppetModel = catalog.models.first { $0.relativePath == "models/broken-puppet-owner.json" }
        let renamedPuppetModel = catalog.models.first { $0.relativePath == "models/renamed-owner.json" }
        let result: [String: Any] = [
            "modelFound": model != nil,
            "solid": model?.isSolidLayer ?? false,
            "materialPath": model?.materialPath ?? "missing",
            "modelDeclaredSizeWH": model?.declaredSizeWH ?? [],
            "barDeclaredSizeWH": barModel?.declaredSizeWH ?? [],
            "materialCatalogPaths": catalog.materials.map(\.relativePath).sorted(),
            "shaderContractIdentities": catalog.shaderContracts.map(\.identity).sorted(),
            "tintScript": tint?.scriptSource ?? "missing",
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
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class SceneAssetCatalogResourceViewTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-scene-catalog-resource-view-"
        )
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

        harness = root / "Harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
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
        cls.binary = root / "scene-catalog-resource-view-harness"
        subprocess.run(
            [
                "xcrun", "--sdk", "macosx", "swiftc",
                *(str(path) for path in sources),
                str(harness), "-o", str(cls.binary),
            ],
            cwd=REPOSITORY_ROOT,
            check=True,
            capture_output=True,
            text=True,
        )
        completed = subprocess.run(
            [str(cls.binary), str(project), str(package), str(stock)],
            cwd=REPOSITORY_ROOT,
            check=True,
            capture_output=True,
            text=True,
        )
        cls.result = json.loads(completed.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

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


if __name__ == "__main__":
    unittest.main()
