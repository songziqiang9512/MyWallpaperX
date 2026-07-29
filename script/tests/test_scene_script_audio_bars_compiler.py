#!/usr/bin/env python3
"""Strict native SceneScript 64-band audio-bars compiler gate."""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SOURCE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SWIFT_SOURCES = [
    SOURCE_ROOT / "Format/SceneJSONValue.swift",
    SOURCE_ROOT / "Format/SceneScriptBindingDefinition.swift",
    SOURCE_ROOT / "Runtime/SceneScriptAudioBarsPlan.swift",
    SOURCE_ROOT / "Runtime/SceneScriptAudioBarsVerification.swift",
    SOURCE_ROOT / "Runtime/SceneScriptAudioBarsCompiler.swift",
]

HARNESS = r'''
import Foundation

enum SceneDocument {
    struct ShaderValue {
        let rawValue: String
        let valueKind: String
        let userBinding: String?
        let components: [Double]?
        let timeline: Int?
        let timelineDiagnostics: [String]
    }
}

struct SceneShaderContract: Codable, Equatable, Sendable {
    enum SourceKind: String, Codable, Equatable, Sendable {
        case authoredSource
        case hostBuiltin
    }
    enum StageKind: String, Codable, Equatable, Sendable {
        case vertex
        case fragment
    }
    struct Stage: Codable, Equatable, Sendable {
        let kind: StageKind
        let relativePath: String
        let source: String
        let rawSHA256: String
    }
    struct Diagnostic: Codable, Equatable, Sendable {
        let code: String
    }
    let identity: String
    let sourceKind: SourceKind
    let stages: [Stage]
    let diagnostics: [Diagnostic]
    let canonicalSHA256: String
}

struct SceneRenderDescriptor {
    struct CameraDescriptor {
        let parallaxEnabled: Bool
        let orthoHeight: Float?
    }
    struct Layer {
        let id: Int
        let contentKind: String
        let imagePath: String?
        let imageAlignment: String?
        let visible: Bool?
        let alpha: Double?
        let colorRGB: [Float]?
        let colorBlendMode: Int?
        let brightness: Double?
        let hasInlineScript: Bool
        let particlePath: String?
        let utilityLayer: Int?
        let dependencyLayerIDs: [Int]
        let parentID: Int?
        let childLayerIDs: [Int]
        let attachmentName: String?
        let parentAttachmentBindFrame: [Float]?
        let puppetAnimationLayers: [Int]
        let puppetMeshPath: String?
        let text: String?
        let textStyle: Int?
        let textScript: Int?
        let effects: [Int]
        let effectFiles: [String]
        let texturePaths: [String]
        let timelines: [Int]
        let timelineDiagnostics: [String]
        let modelCropOffsetXY: [Float]?
        let parallaxDepthXY: [Float]?
        let disablesParallaxPropagation: Bool
        let originXYZ: [Float]?
        let sizeWH: [Float]?
        let scriptBindings: [SceneScriptBindingDefinition]?
    }
    struct ModelMaterialLink {
        let modelPath: String
        let materialPath: String?
    }
    struct MaterialPassDescriptor {
        let materialPath: String
        let materialRawSHA256: String
        let passIndex: Int
        let shaderPath: String?
        let texturePaths: [String]
        let textureSlots: [String?]
        let userTextureInputs: [Int?]
        let combos: [String: Int]
        let constantShaderValues: [String: SceneDocument.ShaderValue]
        let userShaderValues: [String: String]
        let blending: String?
        let depthTest: String?
        let depthWrite: String?
        let cullMode: String?
        let alphaWriting: String?
    }
    let camera: CameraDescriptor
    let layers: [Layer]
    let modelMaterialLinks: [ModelMaterialLink]
    let materialPasses: [MaterialPassDescriptor]
    let missingResources: [String]
}

@main
enum Harness {
    typealias Input = SceneScriptAudioBarsVerificationInput
    static let fixedSHA =
        "2d874f553bef33dfd4650b1d38630148ccf52940bb6b542f46860411aa5d9379"
    static let parameterizedSHA =
        "e6ff1bbde3ab348731a5ba35f757f8f0fc97fd70a117dd7e74eaffe98026b149"
    static let fixedModel = "models/workshop/2079954552/bar.json"
    static let parameterizedModel = "models/workshop/2727665642/bar.json"

    static func main() throws {
        let fixed = compile(input(parameterized: false, layerID: 9001))
        let parameterized = compile(input(parameterized: true, layerID: 7))
        let variant = compile(input(
            parameterized: true,
            layerID: -42,
            properties: parameterizedProperties(
                width: 10, height: 100, x: -60, y: 60,
                angle: -90, alignment: "top"
            )
        ))
        let invalid: [String: SceneScriptAudioBarsProgram] = [
            "unknown": compile(input(
                parameterized: false,
                sourceSHA: String(repeating: "0", count: 64)
            )),
            "binding": compile(input(
                parameterized: false,
                host: "alpha"
            )),
            "propertyType": compile(input(
                parameterized: true,
                properties: parameterizedProperties(widthValue: .string("2.5"))
            )),
            "propertyRange": compile(input(
                parameterized: true,
                properties: parameterizedProperties(width: 10.01)
            )),
            "camera": compile(input(
                parameterized: false,
                layer: layer(parameterized: false, cameraParallax: true)
            )),
            "parallax": compile(input(
                parameterized: false,
                layer: layer(parameterized: false, removeParallax: true)
            )),
            "effects": compile(input(
                parameterized: true,
                layer: layer(parameterized: true, effectCount: 1)
            )),
            "relationships": compile(input(
                parameterized: true,
                layer: layer(parameterized: true, dependencyCount: 1, parentID: 4)
            )),
            "provider": compile(input(
                parameterized: true,
                layer: layer(parameterized: true, reverseDependencyCount: 1)
            )),
            "timeline": compile(input(
                parameterized: true,
                layer: layer(parameterized: true, timelineCount: 1)
            )),
            "missingAsset": compile(input(
                parameterized: false,
                assets: assets(parameterized: false, missingResources: 1)
            )),
            "material": compile(input(
                parameterized: true,
                assets: assets(parameterized: true, materialHash: "mutated")
            )),
            "texture": compile(input(
                parameterized: false,
                assets: assets(parameterized: false, texture: "mutated")
            )),
            "state": compile(input(
                parameterized: true,
                assets: assets(parameterized: true, blending: "normal")
            )),
            "combos": compile(input(
                parameterized: true,
                assets: assets(parameterized: true, combos: [:])
            )),
            "shader": compile(input(
                parameterized: true,
                assets: assets(parameterized: true, mutateStage: true)
            )),
        ]
        let unrelated = SceneScriptAudioBarsCompiler.compile(
            descriptor: unrelatedDescriptor(),
            shaderContracts: []
        )
        let payload: [String: Any] = [
            "fixed": describe(fixed.plans.first),
            "parameterized": describe(parameterized.plans.first),
            "variant": describe(variant.plans.first),
            "invalid": invalid.mapValues { $0.diagnostics.map(\.code.rawValue) },
            "unrelated": [
                "plans": unrelated.plans.count,
                "diagnostics": unrelated.diagnostics.count,
            ],
            "report": fixed.reportLines,
            "empty": [
                "plans": SceneScriptAudioBarsProgram.empty.plans.count,
                "consumer": SceneScriptAudioBarsProgram.empty.hasAudioConsumer,
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }

    static func compile(_ input: Input) -> SceneScriptAudioBarsProgram {
        SceneScriptAudioBarsCompiler.compileVerifiedProfile(input)
    }

    static func input(
        parameterized: Bool,
        layerID: Int = 1,
        sourceSHA: String? = nil,
        host: String = "visible",
        properties: [String: SceneJSONValue]? = nil,
        layer: Input.LayerSnapshot? = nil,
        assets: Input.AssetSnapshot? = nil
    ) -> Input {
        .init(
            layerID: layerID,
            bindingCount: 1,
            host: host,
            sourceSHA256: sourceSHA ?? (parameterized ? parameterizedSHA : fixedSHA),
            properties: properties ?? (
                parameterized ? parameterizedProperties() : [:]
            ),
            authoredValue: .bool(true),
            layer: layer ?? self.layer(parameterized: parameterized),
            assets: assets ?? self.assets(parameterized: parameterized)
        )
    }

    static func layer(
        parameterized: Bool,
        cameraParallax: Bool = false,
        removeParallax: Bool = false,
        effectCount: Int = 0,
        dependencyCount: Int = 0,
        reverseDependencyCount: Int = 0,
        parentID: Int? = nil,
        timelineCount: Int = 0
    ) -> Input.LayerSnapshot {
        let actualParallax: [Float]? =
            removeParallax ? nil : (parameterized ? nil : [1, 1])
        return .init(
            contentKind: "image",
            imagePath: parameterized ? parameterizedModel : fixedModel,
            imageAlignment: parameterized ? nil : "center",
            visible: true,
            alpha: parameterized ? nil : 1,
            colorRGB: parameterized ? nil : [1, 1, 1],
            colorBlendMode: parameterized ? nil : 0,
            brightness: parameterized ? nil : 1,
            hasInlineScript: true,
            particlePath: nil,
            hasUtilityLayer: false,
            dependencyCount: dependencyCount,
            reverseDependencyConsumerCount: reverseDependencyCount,
            parentID: parentID,
            childCount: 0,
            attachmentName: nil,
            hasParentAttachmentBindFrame: false,
            puppetAnimationCount: 0,
            puppetMeshPath: nil,
            text: nil,
            hasTextStyle: false,
            hasTextScript: false,
            effectCount: effectCount,
            effectFileCount: 0,
            texturePathCount: 0,
            timelineCount: timelineCount,
            timelineDiagnosticCount: 0,
            hasModelCropOffset: false,
            parallaxDepthXY: actualParallax,
            disablesParallaxPropagation: false,
            cameraParallaxEnabled: cameraParallax,
            cameraOrthoHeight: 2160,
            hasFiniteOrigin: true,
            hasPositiveFiniteSize: true
        )
    }

    static func assets(
        parameterized: Bool,
        missingResources: Int = 0,
        materialHash: String? = nil,
        texture: String? = nil,
        blending: String = "translucent",
        combos: [String: Int]? = nil,
        mutateStage: Bool = false
    ) -> Input.AssetSnapshot {
        let material = parameterized
            ? "materials/workshop/2727665642/bar.json"
            : "materials/workshop/2079954552/bar.json"
        let actualTexture = texture ?? (
            parameterized ? "workshop/2727665642/bar" : "workshop/2079954552/bar"
        )
        let stages = parameterized ? parameterizedStages(mutated: mutateStage) : [:]
        return .init(
            missingResourceCount: missingResources,
            modelLinkCount: 1,
            linkedMaterialPath: material,
            materialPassCount: 1,
            materialPath: material,
            materialRawSHA256: materialHash ?? (
                parameterized
                    ? "6e9b9f68d9d08f9e3bfa400a6a0102bc144a998d952b14dc35ef7dd16085c3d5"
                    : "65a4ac3ac6d47bc25276b8b3e5f42da54adcec69a68887ac7f0cf475e0af2b7b"
            ),
            materialPassIndex: 0,
            shaderPath: parameterized ? "workshop/2727665642/tint" : "genericimage2",
            texturePaths: [actualTexture],
            textureSlots: [actualTexture],
            userTextureInputCount: 0,
            combos: combos ?? (parameterized ? ["version": 2] : [:]),
            constants: parameterized ? parameterizedConstants() : [:],
            userShaderValues: [:],
            blending: blending,
            depthTest: "disabled",
            depthWrite: "disabled",
            cullMode: "nocull",
            alphaWriting: parameterized ? "default" : nil,
            shaderContractCount: 1,
            shaderIdentity: parameterized ? "workshop/2727665642/tint" : "genericimage2",
            shaderSourceKind: parameterized ? "authoredSource" : "hostBuiltin",
            shaderDiagnosticCount: 0,
            shaderStageCount: parameterized ? 2 : 0,
            shaderDeclaredStageSHA256: stages,
            shaderSourceStageSHA256: stages,
            shaderCanonicalSHA256: parameterized
                ? String(repeating: "a", count: 64)
                : "d29f539dad764c98b38610897d1280d34207ecfe75a934e4f8d03bef52589fde",
            shaderCanonicalMatchesPayload: true
        )
    }

    static func parameterizedProperties(
        width: Double = 2.5,
        height: Double = 50,
        x: Double = 20,
        y: Double = 0,
        angle: Double = 0,
        alignment: String = "centre",
        widthValue: SceneJSONValue? = nil
    ) -> [String: SceneJSONValue] {
        [
            "barWidth": widthValue ?? .number(width),
            "scaleY": .number(height),
            "originX": .number(x),
            "originY": .number(y),
            "anglesY": .number(angle),
            "barAlignmentdir": .string(alignment),
        ]
    }

    static func parameterizedStages(mutated: Bool) -> [String: String] {
        [
            "vertex:shaders/workshop/2727665642/tint.vert":
                mutated
                    ? "mutated"
                    : "0582110d1e8ccfdd0d42779860ffc2915e3eb22cc5013df173592c7dc3ae5730",
            "fragment:shaders/workshop/2727665642/tint.frag":
                "ed1eb09fac286baf5b32b82f742330d3137983aa5694a4d183e72bd4aed68db1",
        ]
    }

    static func parameterizedConstants() -> [String: Input.ShaderValueSnapshot] {
        let invisible = "\u{20}\u{200F}\u{200F}\u{200E}\u{20}"
        return [
            invisible: .init(
                rawValue: "0.0", valueKind: "number", userBinding: nil,
                components: [0], hasTimeline: false, timelineDiagnostics: []
            ),
            "Alpha": .init(
                rawValue: "1.0", valueKind: "number", userBinding: nil,
                components: [1], hasTimeline: false, timelineDiagnostics: []
            ),
            "color": .init(
                rawValue: "1.00000 1.00000 1.00000",
                valueKind: "binding", userBinding: nil,
                components: [1, 1, 1], hasTimeline: false, timelineDiagnostics: []
            ),
        ]
    }

    static func describe(_ plan: SceneScriptAudioBarsPlan?) -> [String: Any] {
        guard let plan else { return [:] }
        return [
            "layerID": plan.layerID,
            "count": plan.barCount,
            "resolution": plan.audioResolution,
            "channel": plan.channel.rawValue,
            "width": plan.widthMultiplier,
            "height": plan.heightMultiplier,
            "depth": plan.depthMultiplier,
            "xStep": plan.xStep,
            "yStep": plan.yStep,
            "angle": plan.angleDegrees,
            "alignment": plan.alignment.rawValue,
            "firstStep": plan.stepIndex(forBarIndex: 0),
            "heightAt2_25": plan.height(forSpectrumValue: 2.25),
            "consumer": plan.hasAudioConsumer,
        ]
    }

    static func unrelatedDescriptor() -> SceneRenderDescriptor {
        let binding = SceneScriptBindingDefinition(
            host: "visible",
            source: "self-authored unrelated fixture",
            properties: [:],
            authoredValue: .bool(true)
        )
        let layer = SceneRenderDescriptor.Layer(
            id: 1, contentKind: "image", imagePath: "models/fixture.json",
            imageAlignment: nil, visible: true, alpha: nil, colorRGB: nil,
            colorBlendMode: nil, brightness: nil, hasInlineScript: true,
            particlePath: nil, utilityLayer: nil, dependencyLayerIDs: [],
            parentID: nil, childLayerIDs: [], attachmentName: nil,
            parentAttachmentBindFrame: nil, puppetAnimationLayers: [],
            puppetMeshPath: nil, text: nil, textStyle: nil, textScript: nil,
            effects: [], effectFiles: [], texturePaths: [], timelines: [],
            timelineDiagnostics: [], modelCropOffsetXY: nil, parallaxDepthXY: nil,
            disablesParallaxPropagation: false, originXYZ: [0, 0, 0],
            sizeWH: [4, 4], scriptBindings: [binding]
        )
        return .init(
            camera: .init(parallaxEnabled: false, orthoHeight: 2160),
            layers: [layer],
            modelMaterialLinks: [],
            materialPasses: [],
            missingResources: []
        )
    }
}
'''


class SceneScriptAudioBarsCompilerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temp = tempfile.TemporaryDirectory(prefix="mwx-script-audio-bars-")
        root = Path(cls.temp.name)
        harness = root / "Harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        binary = root / "scene-script-audio-bars"
        env = os.environ.copy()
        env["CLANG_MODULE_CACHE_PATH"] = str(root / "clang-cache")
        env["SWIFT_MODULECACHE_PATH"] = str(root / "swift-cache")
        compilation = subprocess.run(
            ["swiftc", *(str(path) for path in SWIFT_SOURCES), str(harness), "-o", str(binary)],
            capture_output=True,
            text=True,
            env=env,
        )
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)
        execution = subprocess.run(
            [str(binary)], capture_output=True, text=True, check=True, env=env
        )
        cls.payload = json.loads(execution.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temp.cleanup()

    def test_both_profiles_compile_to_one_generic_unclamped_plan(self) -> None:
        fixed = self.payload["fixed"]
        self.assertAlmostEqual(fixed.pop("xStep"), 5.6, places=5)
        self.assertAlmostEqual(fixed.pop("yStep"), 11.3, places=5)
        self.assertEqual(
            fixed,
            {
                "alignment": "centre",
                "angle": 60,
                "channel": "average",
                "consumer": True,
                "count": 64,
                "depth": 1,
                "firstStep": 1,
                "height": 50,
                "heightAt2_25": 112.5,
                "layerID": 9001,
                "resolution": 64,
                "width": 1,
            },
        )
        parameterized = self.payload["parameterized"]
        self.assertEqual(parameterized["firstStep"], 0)
        self.assertEqual(parameterized["depth"], 0)
        self.assertEqual(parameterized["width"], 2.5)
        self.assertEqual(parameterized["heightAt2_25"], 112.5)

    def test_parameterized_profile_reads_exact_typed_bounded_properties(self) -> None:
        variant = self.payload["variant"]
        self.assertEqual(variant["layerID"], -42)
        self.assertEqual(variant["alignment"], "top")
        self.assertEqual(variant["width"], 10)
        self.assertEqual(variant["height"], 100)
        self.assertEqual(variant["xStep"], -60)
        self.assertEqual(variant["yStep"], 60)
        self.assertEqual(variant["angle"], -90)
        self.assertEqual(self.payload["invalid"]["propertyType"], ["invalidProperties"])
        self.assertEqual(self.payload["invalid"]["propertyRange"], ["invalidProperties"])

    def test_binding_layer_and_complete_asset_mutations_fail_closed(self) -> None:
        invalid = self.payload["invalid"]
        self.assertEqual(invalid["unknown"], ["unknownProfile"])
        self.assertEqual(invalid["binding"], ["invalidBinding"])
        for key in ("camera", "parallax", "effects", "relationships", "provider", "timeline"):
            with self.subTest(key=key):
                self.assertEqual(invalid[key], ["invalidLayerContract"])
        for key in ("missingAsset", "material", "texture", "state", "combos", "shader"):
            with self.subTest(key=key):
                self.assertEqual(invalid[key], ["invalidAssetContract"])

    def test_unrelated_scripts_are_ignored_and_report_contract_is_stable(self) -> None:
        self.assertEqual(self.payload["unrelated"], {"plans": 0, "diagnostics": 0})
        self.assertEqual(self.payload["empty"], {"plans": 0, "consumer": False})
        self.assertEqual(
            self.payload["report"][:3],
            [
                "sceneScriptAudioBarsPlanCount: 1",
                "sceneScriptAudioBarsDiagnosticCount: 0",
                "sceneScriptAudioBarsHasAudioConsumer: true",
            ],
        )


if __name__ == "__main__":
    unittest.main()
