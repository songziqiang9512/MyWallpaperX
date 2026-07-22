#!/usr/bin/env python3

from __future__ import annotations

import json
import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SOURCE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SWIFT_SOURCES = [
    SOURCE_ROOT / "SceneDocument.swift",
    SOURCE_ROOT / "SceneDocument+NumericParsing.swift",
    SOURCE_ROOT / "SceneUtilityLayer.swift",
    SOURCE_ROOT / "SceneRenderDescriptor.swift",
    SOURCE_ROOT / "SceneMetalPipeline.swift",
    SOURCE_ROOT / "SceneSolidLayerTexture.swift",
]


SCENE_FIXTURE = {
    "version": 3,
    "objects": [
        {
            "id": 10,
            "name": "Plain solid",
            "image": "models/util/solidlayer.json",
            "color": "0.1 0.2 0.3",
            "size": "1920 1080",
            "alpha": 0.75,
        },
        {
            "id": 20,
            "name": "Wrapped solid",
            "image": "models/util/solidlayer.json",
            "color": {"value": "0.4 0.5 0.6"},
            "size": "640 480",
            "alpha": {"script": "export function update() {}", "value": 0},
        },
        {
            "id": 30,
            "name": "Default white solid",
            "image": "models/util/solidlayer.json",
            "size": "320 200",
            "alpha": {"user": "opacity", "value": 0.25},
        },
        {
            "id": 40,
            "name": "Regular image",
            "image": "models/user/photo.json",
            "size": "100 100",
        },
    ],
}


HARNESS_SOURCE = r'''
import Foundation
import Metal

struct SceneParticleInstanceOverride: Codable {}

struct SceneParticleDefinitionParser {
    func parseInstanceOverride(_ raw: Any?) -> SceneParticleInstanceOverride? { nil }
}

struct SceneTextDescriptor: Codable {
    let padding: Float

    init(padding: Float = 0) {
        self.padding = padding
    }

    static func parse(_ root: [String: Any]) -> SceneTextDescriptor { .init() }
}

enum SceneTextGeometry {
    static func expandedSize(authoredSize: [Float]?, padding: Float) -> [Float]? {
        authoredSize
    }
}

enum SceneUserPropertyValue {}

struct SceneUserPropertyCatalog {
    static let empty = SceneUserPropertyCatalog()
}

struct SceneUserPropertyResolution {
    let root: [String: Any]
}

struct SceneUserPropertyDocumentResolver {
    func resolve(
        root: [String: Any],
        catalog: SceneUserPropertyCatalog,
        overrides: [String: SceneUserPropertyValue]
    ) -> SceneUserPropertyResolution {
        SceneUserPropertyResolution(root: root)
    }
}

struct ScenePkgExtractionReport {
    let outputURL: URL?
}

struct SceneProject {
    let rootURL: URL
    let entryPath: String
    let userProperties: SceneUserPropertyCatalog

    var entryURL: URL { rootURL.appendingPathComponent(entryPath) }
}

struct SceneAssetCatalog {
    struct ModelAsset {
        let relativePath: String
        let materialPath: String?
        let cropOffsetXY: [Float]?
        let isSolidLayer: Bool
    }

    struct MaterialAsset {
        struct Pass {
            let shader: String?
            let textures: [String]
            let textureSlots: [String?]
            let combos: [String: Int]
            let constantShaderValues: [String: SceneDocument.ShaderValue]
            let blending: String?
            let depthTest: String?
            let depthWrite: String?
            let cullMode: String?
        }

        let relativePath: String
        let passes: [Pass]
    }

    let models: [ModelAsset]
    let materials: [MaterialAsset]
    let shaderReferences: [String]
    let textureReferences: [String]
}

struct SceneResourceReferenceIndex {
    let missingReferences: [String]
    let builtInReferenceCount: Int
}

struct SceneCapabilityProfile {
    let firstStageRendererGaps: [String]
}

struct SceneDiagnosticsReport {
    let project: SceneProject?
    let sceneDocument: SceneDocument?
    let assetCatalog: SceneAssetCatalog?
    let resourceReferences: SceneResourceReferenceIndex?
    let capabilityProfile: SceneCapabilityProfile?
}

@main
enum Harness {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else { throw HarnessError.missingFixture }
        let sceneURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let document = try SceneDocumentLoader().load(from: sceneURL)
        let project = SceneProject(
            rootURL: sceneURL.deletingLastPathComponent(),
            entryPath: sceneURL.lastPathComponent,
            userProperties: .empty
        )
        let descriptor = SceneRenderDescriptorBuilder().build(
            project: project,
            sceneDocument: document,
            assetCatalog: SceneAssetCatalog(
                models: [], materials: [], shaderReferences: [], textureReferences: []
            ),
            resourceReferences: SceneResourceReferenceIndex(
                missingReferences: [], builtInReferenceCount: 3
            ),
            capabilityProfile: SceneCapabilityProfile(firstStageRendererGaps: [])
        )

        guard let device = MTLCreateSystemDefaultDevice(),
              let solidTexture = SceneSolidLayerTexture.make(device: device) else {
            throw HarnessError.noMetal
        }
        var pixel = [UInt8](repeating: 0, count: 4)
        solidTexture.getBytes(
            &pixel,
            bytesPerRow: 4,
            from: MTLRegionMake2D(0, 0, 1, 1),
            mipmapLevel: 0
        )

        let uniform = SceneLayerFragmentUniforms(
            time: 0,
            alpha: 0.75,
            effectFlags: 0,
            dependencyBlendMode: 0,
            cursorUV: .zero,
            _pad1: .zero,
            tint: SIMD4(0.1, 0.2, 0.3, 1),
            effectParams0: .zero,
            effectParams1: .zero,
            effectParams2: .zero,
            effectParams3: .zero,
            textureFrame0: SIMD4(0, 0, 1, 0),
            textureFrame1: SIMD4(0, 1, 0, 0)
        )

        let objects = Dictionary(uniqueKeysWithValues: document.objects.map { ($0.id, $0) })
        let layers = Dictionary(uniqueKeysWithValues: descriptor.layers.map { ($0.id, $0) })
        let result: [String: Any] = [
            "documentColors": [10, 20, 30].map { objects[$0]?.colorRGB ?? [] },
            "contentKinds": [10, 20, 30, 40].map { layers[$0]?.contentKind ?? "" },
            "descriptorColors": [10, 20, 30].map { layers[$0]?.colorRGB ?? [] },
            "documentAlphas": [10, 20, 30, 40].map { objects[$0]?.alpha ?? -1 },
            "descriptorAlphas": [10, 20, 30, 40].map { layers[$0]?.alpha ?? -1 },
            "imageRenderable": [10, 20, 30, 40].map {
                layers[$0]?.isImageRenderable ?? false
            },
            "uniformTint": [uniform.tint.x, uniform.tint.y, uniform.tint.z, uniform.tint.w],
            "textureSize": [solidTexture.width, solidTexture.height],
            "texturePixel": pixel,
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }

    enum HarnessError: Error {
        case missingFixture
        case noMetal
    }
}
'''


class SceneSolidLayerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        swiftc = shutil.which("swiftc")
        if swiftc is None:
            raise unittest.SkipTest("swiftc is unavailable")
        missing_sources = [path for path in SWIFT_SOURCES if not path.is_file()]
        if missing_sources:
            raise RuntimeError(
                "Scene solid production contract is missing: "
                + ", ".join(path.name for path in missing_sources)
            )

        cls.temporary_directory = tempfile.TemporaryDirectory(prefix="mwx-scene-solid-")
        directory = Path(cls.temporary_directory.name)
        fixture = directory / "scene.json"
        fixture.write_text(json.dumps(SCENE_FIXTURE), encoding="utf-8")
        harness = directory / "Harness.swift"
        harness.write_text(HARNESS_SOURCE, encoding="utf-8")
        cls.binary = directory / "scene-solid-layers"
        compilation = subprocess.run(
            [
                "xcrun",
                "--sdk",
                "macosx",
                "swiftc",
                *(str(path) for path in SWIFT_SOURCES),
                str(harness),
                "-framework",
                "Metal",
                "-o",
                str(cls.binary),
            ],
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)
        completed = subprocess.run(
            [str(cls.binary), str(fixture)],
            check=True,
            capture_output=True,
            text=True,
        )
        cls.result = json.loads(completed.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        if hasattr(cls, "temporary_directory"):
            cls.temporary_directory.cleanup()

    def test_solid_layer_classification_and_renderability(self) -> None:
        self.assertEqual(self.result["contentKinds"], ["solid", "solid", "solid", "image"])
        self.assertEqual(self.result["imageRenderable"], [True, True, True, True])

    def test_plain_wrapped_and_missing_colors_resolve_to_rgb(self) -> None:
        document_expected = [[0.1, 0.2, 0.3], [0.4, 0.5, 0.6], []]
        descriptor_expected = [[0.1, 0.2, 0.3], [0.4, 0.5, 0.6], []]
        for actual_colors, expected_colors in (
            (self.result["documentColors"], document_expected),
            (self.result["descriptorColors"], descriptor_expected),
        ):
            for actual, wanted in zip(actual_colors, expected_colors):
                self.assertEqual(len(actual), len(wanted))
                for component, expected_component in zip(actual, wanted):
                    self.assertAlmostEqual(component, expected_component, places=6)

    def test_plain_script_and_user_wrapped_alpha_preserve_authored_value(self) -> None:
        expected = [0.75, 0, 0.25, -1]
        self.assertEqual(self.result["documentAlphas"], expected)
        self.assertEqual(self.result["descriptorAlphas"], expected)

    def test_fragment_uniform_carries_layer_tint(self) -> None:
        for actual, expected in zip(self.result["uniformTint"], [0.1, 0.2, 0.3, 1]):
            self.assertAlmostEqual(actual, expected, places=6)

        compositor = (SOURCE_ROOT / "SceneImageLayerCompositor.swift").read_text(
            encoding="utf-8"
        )
        shader = (SOURCE_ROOT / "SceneMetalPipeline.swift").read_text(encoding="utf-8")
        self.assertRegex(
            compositor,
            re.compile(
                r'tint\s*:\s*request\.layer\.contentKind\s*==\s*"solid"'
                r"[\s\S]{0,200}request\.layer\.colorRGB"
            ),
        )
        self.assertRegex(
            compositor,
            re.compile(r"SceneLayerFragmentUniforms\([\s\S]{0,900}\btint\s*:\s*SIMD4\(tint\.x"),
        )
        self.assertRegex(shader, re.compile(r"\bu\.tint\b"))

    def test_one_white_texture_is_reused_for_every_solid_layer(self) -> None:
        self.assertEqual(self.result["textureSize"], [1, 1])
        self.assertEqual(self.result["texturePixel"], [255, 255, 255, 255])

        view = (SOURCE_ROOT / "SceneMetalView.swift").read_text(encoding="utf-8")
        self.assertRegex(view, r"private let solidLayerTexture\s*:\s*MTLTexture\??")
        self.assertEqual(view.count("SceneSolidLayerTexture.make("), 1)
        self.assertRegex(
            view,
            re.compile(
                r'if layer\.contentKind\s*==\s*"solid"'
                r"[\s\S]{0,400}guard let texture\s*=\s*solidLayerTexture"
                r"[\s\S]{0,400}loaded\[layer\.id\]\s*=\s*texture"
            ),
        )
        self.assertNotRegex(view, r"SceneSolidLayerTexture\.make\([^)]*color")


if __name__ == "__main__":
    unittest.main()
