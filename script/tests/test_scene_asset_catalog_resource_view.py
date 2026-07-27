#!/usr/bin/env python3

from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SWIFT_SOURCES = [
    SCENE_ROOT / "Format/SceneJSONValue.swift",
    SCENE_ROOT / "Format/SceneDocument+NumericParsing.swift",
    SCENE_ROOT / "Format/SceneProject.swift",
    SCENE_ROOT / "Properties/SceneUserProperty.swift",
    SCENE_ROOT / "Properties/SceneUserPropertyDefinitionParser.swift",
    SCENE_ROOT / "Resources/SceneResourceIndex.swift",
    SCENE_ROOT / "Resources/SceneResourceView.swift",
    SCENE_ROOT / "Resources/SceneAssetCatalog.swift",
    SCENE_ROOT / "RenderGraph/SceneEffectDefinition.swift",
    SCENE_ROOT / "RenderGraph/SceneEffectTextureInput.swift",
    SCENE_ROOT / "RenderGraph/SceneShaderContract.swift",
    SCENE_ROOT / "RenderGraph/SceneShaderContractLoader.swift",
]

HARNESS = r'''
import Foundation

struct ScenePkgExtractionReport {
    let outputURL: URL?
}

struct SceneMdlPuppetAttachment {}

enum SceneMdlPuppetAttachmentReader {
    static func read(data: Data) throws -> [SceneMdlPuppetAttachment] { [] }
}

enum SceneDocument {
    struct ShaderValue: Codable {
        let rawValue: String
        let valueKind: String
        let userBinding: String?
        let components: [Double]?
    }
}

enum SceneDocumentLoader {}

@main
enum Harness {
    static func main() throws {
        let projectRoot = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let packageRoot = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        let stockRoot = URL(fileURLWithPath: CommandLine.arguments[3], isDirectory: true)
        let project = try SceneProjectLoader().load(from: projectRoot)
        let catalog = try SceneAssetCatalogLoader().load(
            project: project,
            packageReport: ScenePkgExtractionReport(outputURL: packageRoot),
            referencedResourcePaths: ["models/util/solidlayer_depthtest.json"],
            stockAssetsRootURL: stockRoot
        )
        let model = catalog.models.first {
            $0.relativePath == "models/util/solidlayer_depthtest.json"
        }
        let result: [String: Any] = [
            "modelFound": model != nil,
            "solid": model?.isSolidLayer ?? false,
            "materialPath": model?.materialPath ?? "missing",
            "materialCatalogCount": catalog.materials.count,
            "shaderContractCount": catalog.shaderContracts.count,
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

        harness = root / "Harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        cls.binary = root / "scene-catalog-resource-view-harness"
        subprocess.run(
            [
                "xcrun", "--sdk", "macosx", "swiftc",
                *(str(path) for path in SWIFT_SOURCES),
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
        self.assertEqual(self.result["materialCatalogCount"], 0)
        self.assertEqual(self.result["shaderContractCount"], 0)


if __name__ == "__main__":
    unittest.main()
