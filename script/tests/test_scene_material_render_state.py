#!/usr/bin/env python3

import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = REPO_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SWIFT_SOURCES = [
    SCENE_ROOT / "Format/SceneJSONValue.swift",
    SCENE_ROOT / "Format/SceneDocument+NumericParsing.swift",
    SCENE_ROOT / "Format/SceneProject.swift",
    SCENE_ROOT / "Properties/SceneUserProperty.swift",
    SCENE_ROOT / "Properties/SceneUserPropertyDefinitionParser.swift",
    SCENE_ROOT / "Resources/SceneResourceIndex.swift",
    SCENE_ROOT / "Resources/SceneAssetCatalog.swift",
    SCENE_ROOT / "RenderGraph/SceneEffectDefinition.swift",
    SCENE_ROOT / "RenderGraph/SceneEffectTextureInput.swift",
    SCENE_ROOT / "RenderGraph/SceneShaderContract.swift",
    SCENE_ROOT / "RenderGraph/SceneShaderContractLoader.swift",
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
                    cullMode: $0.cullMode
                )
            }
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        FileHandle.standardOutput.write(try encoder.encode(states))
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
        cls.states = json.loads(completed.stdout)

    @classmethod
    def tearDownClass(cls):
        cls.build_directory.cleanup()

    def test_canonical_render_state_spellings_are_parsed(self):
        self.assertEqual(self.states["materials/canonical.json"], [{
            "blending": "translucent",
            "depthTest": "disabled",
            "depthWrite": "disabled",
            "cullMode": "nocull",
        }])

    def test_official_compatibility_spellings_reach_the_same_state_ir(self):
        self.assertEqual(self.states["materials/compat.json"], [{
            "blending": "additive",
            "depthTest": "disabled",
            "depthWrite": "disabled",
            "cullMode": "nocull",
        }])

    def test_canonical_spelling_wins_when_both_are_present(self):
        self.assertEqual(self.states["materials/both.json"], [{
            "depthTest": "enabled",
            "depthWrite": "enabled",
            "cullMode": "normal",
        }])


if __name__ == "__main__":
    unittest.main()
