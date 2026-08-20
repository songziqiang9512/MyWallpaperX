#!/usr/bin/env python3

import json
import sys
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


SOURCE_SET_SCRIPT_ROOT = Path(__file__).resolve().parents[1]
if str(SOURCE_SET_SCRIPT_ROOT) not in sys.path:
    sys.path.insert(0, str(SOURCE_SET_SCRIPT_ROOT))

from scene_swift_source_sets import scene_swift_sources_by_basename


REPO_ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = REPO_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SHADER_CONTRACT_RESOURCE_RESOLUTION_SOURCES = scene_swift_sources_by_basename(
    "shader_contract_resource_resolution"
)
SWIFT_SOURCES = [
    SHADER_CONTRACT_RESOURCE_RESOLUTION_SOURCES["SceneJSONValue.swift"],
    SCENE_ROOT / "Format/SceneCompatibilityContext.swift",
    SCENE_ROOT / "Format/SceneDocument+NumericParsing.swift",
    SCENE_ROOT / "Format/SceneProject.swift",
    SCENE_ROOT / "Properties/SceneUserProperty.swift",
    SCENE_ROOT / "Properties/SceneUserPropertyDefinitionParser.swift",
    SHADER_CONTRACT_RESOURCE_RESOLUTION_SOURCES["SceneResourceIndex.swift"],
    SHADER_CONTRACT_RESOURCE_RESOLUTION_SOURCES["SceneResourceView.swift"],
    SCENE_ROOT / "Resources/SceneAssetCatalog.swift",
    SCENE_ROOT / "RenderGraph/SceneEffectDefinition.swift",
    SCENE_ROOT / "RenderGraph/SceneEffectTextureInput.swift",
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

# SceneDocument 的完整图会拉入 particle/utility/puppet/text 全套，与 material pass 解析无关，
# 因此只为它的容器类型留最小替身；packageReport 只提供 outputURL，puppet 附件不参与
# material pass 解析。loadMaterial 及其依赖的 numeric parsing 全部编译真实源码。
HARNESS = r"""
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

private struct PassState: Codable {
    let blending: String?
    let depthTest: String?
    let depthWrite: String?
    let cullMode: String?
    let alphaWriting: String?
    let userShaderValues: [String: String]
}

private struct HashState: Codable {
    let raw: String
    let shaderPathIndependent: String
}

private struct CatalogState: Codable {
    let states: [String: [PassState]]
    let hashes: [String: HashState]
}

@main
private enum MaterialRenderStateHarness {
    static func main() throws {
        let rootURL = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let project = try SceneProjectLoader().load(from: rootURL)
        let catalog = try SceneAssetCatalogLoader().load(project: project, packageReport: nil)
        let states = catalog.materials.reduce(into: [String: [PassState]]()) { result, material in
            result[material.relativePath] = material.passes.map {
                PassState(
                    blending: $0.blending,
                    depthTest: $0.depthTest,
                    depthWrite: $0.depthWrite,
                    cullMode: $0.cullMode,
                    alphaWriting: $0.alphaWriting,
                    userShaderValues: $0.userShaderValues
                )
            }
        }
        let hashes = catalog.materials.reduce(into: [String: HashState]()) {
            $0[$1.relativePath] = HashState(
                raw: $1.rawSHA256,
                shaderPathIndependent: $1.shaderPathIndependentSHA256
            )
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        FileHandle.standardOutput.write(try encoder.encode(CatalogState(
            states: states,
            hashes: hashes
        )))
    }
}
"""

# 官方随包实测拼写：canonical 来自 assets/materials，compat 来自 defaultprojects/ricepod
# 与 assets/materials/util 的历史 material，两套必须解析成同一份 render state IR。
MATERIALS = {
    "canonical": {
        "passes": [{
            "blending": "translucent",
            "depthtest": "disabled",
            "depthwrite": "disabled",
            "cullmode": "nocull",
        }]
    },
    "compat": {
        "passes": [{
            "blending": "additive",
            "depthtesting": "disabled",
            "depthwriting": "disabled",
            "culling": "nocull",
        }]
    },
    "both": {
        "passes": [{
            "depthtest": "enabled",
            "depthtesting": "disabled",
            "depthwrite": "enabled",
            "depthwriting": "disabled",
            "cullmode": "normal",
            "culling": "nocull",
        }]
    },
    # alphawriting 与 usershadervalues 只出现在 material 文件，随包各 60/36 处；
    # usershadervalues 的语义是「shader 值名 -> 用户属性名」，与 constantshadervalues 并列。
    "bindings": {
        "passes": [{
            "blending": "normal",
            "alphawriting": "enabled",
            "constantshadervalues": {"roughness": 0.5},
            "usershadervalues": {"schemecolor": "tint", "bgcolor": "tint2"},
        }]
    },
    "shader_path_a": {
        "passes": [{
            "blending": "normal",
            "cullmode": "nocull",
            "depthtest": "disabled",
            "depthwrite": "disabled",
            "shader": "effects/waterwaves",
        }]
    },
    "shader_path_b": {
        "passes": [{
            "blending": "normal",
            "cullmode": "nocull",
            "depthtest": "disabled",
            "depthwrite": "disabled",
            "shader": "workshop/912345678/effects/waterwaves",
        }]
    },
}


class SceneMaterialRenderStateTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        swiftc = shutil.which("swiftc")
        if swiftc is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.build_directory = tempfile.TemporaryDirectory()
        build_root = Path(cls.build_directory.name)
        harness = build_root / "MaterialRenderStateHarness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        cls.binary = build_root / "material-render-state-harness"
        subprocess.run(
            [
                swiftc,
                *(str(path) for path in SWIFT_SOURCES),
                str(harness),
                "-o",
                str(cls.binary),
            ],
            cwd=REPO_ROOT,
            check=True,
            capture_output=True,
            text=True,
        )

        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory) / "wallpaper"
            (root / "materials").mkdir(parents=True)
            (root / "project.json").write_text(
                json.dumps({"type": "scene", "file": "scene.json"}),
                encoding="utf-8",
            )
            (root / "scene.json").write_text("{}", encoding="utf-8")
            for name, payload in MATERIALS.items():
                (root / "materials" / f"{name}.json").write_text(
                    json.dumps(payload), encoding="utf-8"
                )
            completed = subprocess.run(
                [str(cls.binary), str(root)],
                cwd=REPO_ROOT,
                check=True,
                capture_output=True,
                text=True,
            )
        cls.result = json.loads(completed.stdout)
        cls.states = cls.result["states"]

    @classmethod
    def tearDownClass(cls):
        cls.build_directory.cleanup()

    def test_canonical_render_state_spellings_are_parsed(self):
        self.assertEqual(self.states["materials/canonical.json"], [{
            "blending": "translucent",
            "depthTest": "disabled",
            "depthWrite": "disabled",
            "cullMode": "nocull",
            "userShaderValues": {},
        }])

    def test_official_compatibility_spellings_reach_the_same_state_ir(self):
        self.assertEqual(self.states["materials/compat.json"], [{
            "blending": "additive",
            "depthTest": "disabled",
            "depthWrite": "disabled",
            "cullMode": "nocull",
            "userShaderValues": {},
        }])

    def test_canonical_spelling_wins_when_both_are_present(self):
        self.assertEqual(self.states["materials/both.json"], [{
            "depthTest": "enabled",
            "depthWrite": "enabled",
            "cullMode": "normal",
            "userShaderValues": {},
        }])

    def test_alpha_writing_and_user_shader_value_bindings_are_preserved(self):
        self.assertEqual(self.states["materials/bindings.json"], [{
            "blending": "normal",
            "alphaWriting": "enabled",
            "userShaderValues": {"schemecolor": "tint", "bgcolor": "tint2"},
        }])

    def test_shader_path_independent_hash_preserves_shape_across_relocation(self):
        first = self.result["hashes"]["materials/shader_path_a.json"]
        second = self.result["hashes"]["materials/shader_path_b.json"]
        self.assertNotEqual(first["raw"], second["raw"])
        self.assertEqual(
            first["shaderPathIndependent"],
            second["shaderPathIndependent"],
        )
        self.assertEqual(
            first["shaderPathIndependent"],
            "f07dfa1b7f21c1c99742c66dfa14ab8c747ebc78a1a7573680329950ad40e121",
        )


if __name__ == "__main__":
    unittest.main()
