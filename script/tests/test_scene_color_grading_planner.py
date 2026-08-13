#!/usr/bin/env python3

from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SOURCE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SWIFT_SOURCES = [
    SOURCE_ROOT / "Format/SceneJSONValue.swift",
    SOURCE_ROOT / "RenderGraph/SceneEffectDefinition.swift",
    SOURCE_ROOT / "RenderGraph/AuthoredGraph/SceneAuthoredEffectRenderPlan.swift",
    SOURCE_ROOT / "RenderGraph/SceneAuthoredMaterialResolver.swift",
    SOURCE_ROOT / "RenderGraph/SceneShaderSourceGraph.swift",
    SOURCE_ROOT / "RenderGraph/SceneShaderContract.swift",
    SOURCE_ROOT / "RenderGraph/SceneColorGradingExecutionPlan.swift",
    SOURCE_ROOT / "RenderGraph/SceneAuthoredColorGradingPlanner.swift",
]


HARNESS = r'''
import CryptoKit
import Foundation

struct SceneEffectTextureInput {}

struct SceneUtilityLayer {
    enum Kind { case fullscreen }
    let kind: Kind
}

struct SceneDocument {
    struct ShaderValue {
        let rawValue: String
        let valueKind: String
        let userBinding: String?
        let components: [Double]?
    }
}

struct SceneRenderDescriptor {
    struct EffectDescriptor {
        struct PassDescriptor {
            let passIndex: Int
            let texturePaths: [String]
            let textureSlots: [String?]
            let userTextureInputs: [SceneEffectTextureInput?]
            let combos: [String: Int]
            let constantShaderValues: [String: SceneDocument.ShaderValue]
            let constantShaderValueKeys: [String]
        }
        let id: String
        let file: String
        let visible: Bool?
        let passes: [PassDescriptor]
    }

    struct Layer {
        let id: Int
        let contentKind: String
        let utilityLayer: SceneUtilityLayer?
        let childLayerIDs: [Int]
        let dependencyLayerIDs: [Int]
        let effects: [EffectDescriptor]
    }

    struct MaterialPassDescriptor {
        let id: String
        let materialPath: String
        let materialRawSHA256: String
        let passIndex: Int
        let shaderPath: String?
        let texturePaths: [String]
        let textureSlots: [String?]
        let userTextureInputs: [SceneEffectTextureInput?]
        let combos: [String: Int]
        let constantShaderValues: [String: SceneDocument.ShaderValue]
        let userShaderValues: [String: String]
        let blending: String?
        let depthTest: String?
        let depthWrite: String?
        let cullMode: String?
        let alphaWriting: String?
    }

    let layers: [Layer]
    let materialPasses: [MaterialPassDescriptor]
    let effectDefinitions: [SceneEffectDefinition]
}

@main
enum Harness {
    typealias Graph = SceneAuthoredEffectRenderPlan
    static let layerID = 31
    static let descriptorID = "31#effect#1"
    static let definitionPath = "effects/fixture/color-grade/effect.json"
    static let materialPath = "materials/fixture/color-grade.json"
    static let shaderIdentity = "fixture/color-grade"
    static let definitionHash =
        "8d6a7a8a43f3373c25cf8d21ef4613dde9170a3f25a5c18269bfca4de6bf5112"
    static let materialHash =
        "fc2f7c7d839ded3fbc632b58ee268b9bddd73fb93d50538e94276a331dde5c9a"
    static let vertexHash =
        "faa7cc72454fd73cc05f0c4bc72e3790a739c060c1ec527030dc31084a93da7a"
    static let fragmentHash =
        "a937fdbb89d040ecb71591b3da76dd47c5df819b92311ce3a8804a40c470804f"

    struct Options {
        var contentKind = "fullscreen"
        var utility = true
        var children: [Int] = []
        var dependencies: [Int] = []
        var definitionHash = Harness.definitionHash
        var materialHash = Harness.materialHash
        var definitionExtra = false
        var texture = false
        var materialUserValue = false
        var blending = "normal"
        var alphaWriting: String?
        var combos = ["TOOLS": 2]
        var brightness = 0.0
        var contrast = 0.17
        var luminance = -0.01
        var saturation = 0.2
        var vibrance = 0.31
        var opacity = 1.0
        var influence = [1.0, 1.0, 1.0]
        var boundKey: String?
        var extraConstant = false
        var omitConstant: String?
        var visible: Bool? = true
    }

    static func value(
        _ components: [Double],
        kind: String,
        binding: String? = nil
    ) -> SceneDocument.ShaderValue {
        .init(
            rawValue: components.map { String($0) }.joined(separator: " "),
            valueKind: kind,
            userBinding: binding,
            components: components
        )
    }

    static func constants(_ options: Options) -> [String: SceneDocument.ShaderValue] {
        var result = [
            "Brightness": value(
                [options.brightness], kind: "number",
                binding: options.boundKey == "brightness" ? "fixture" : nil
            ),
            "Channel influence": value(
                options.influence, kind: "vector",
                binding: options.boundKey == "channel influence" ? "fixture" : nil
            ),
            "Contrast": value(
                [options.contrast], kind: "number",
                binding: options.boundKey == "contrast" ? "fixture" : nil
            ),
            "Luminance": value(
                [options.luminance], kind: "number",
                binding: options.boundKey == "luminance" ? "fixture" : nil
            ),
            "Opacity": value(
                [options.opacity], kind: "number",
                binding: options.boundKey == "opacity" ? "fixture" : nil
            ),
            "Saturation": value(
                [options.saturation], kind: "number",
                binding: options.boundKey == "saturation" ? "fixture" : nil
            ),
            "Vibrance": value(
                [options.vibrance], kind: "number",
                binding: options.boundKey == "vibrance" ? "fixture" : nil
            ),
        ]
        if let omitted = options.omitConstant {
            result.removeValue(forKey: omitted)
        }
        if options.extraConstant {
            result["Future"] = value([1], kind: "number")
        }
        return result
    }

    static func definition(_ options: Options) -> SceneEffectDefinition {
        .init(
            relativePath: definitionPath,
            version: 1,
            replacementKey: "color_grading",
            name: "Color Grading",
            description: nil,
            group: "localeffects",
            performance: nil,
            previewPath: nil,
            editable: false,
            passes: [.init(
                passIndex: 0,
                materialPath: materialPath,
                target: nil,
                bindings: [],
                compose: nil,
                command: nil,
                source: nil,
                conditions: nil,
                extraFields: [:]
            )],
            framebuffers: [],
            dependencies: [
                materialPath,
                "shaders/\(shaderIdentity).frag",
                "shaders/\(shaderIdentity).vert",
            ],
            functions: nil,
            gizmos: nil,
            extraFields: options.definitionExtra ? ["future": .bool(true)] : [:],
            unknownFieldPaths: options.definitionExtra ? ["future"] : [],
            rawSHA256: options.definitionHash
        )
    }

    static func descriptor(_ options: Options = .init()) -> SceneRenderDescriptor {
        let authored = constants(options)
        let textures = options.texture ? ["fixture.tex"] : []
        let slots: [String?] = options.texture ? ["fixture.tex"] : []
        let effect = SceneRenderDescriptor.EffectDescriptor(
            id: descriptorID,
            file: definitionPath,
            visible: options.visible,
            passes: [.init(
                passIndex: 0,
                texturePaths: textures,
                textureSlots: slots,
                userTextureInputs: [],
                combos: options.combos,
                constantShaderValues: authored,
                constantShaderValueKeys: Array(authored.keys).sorted()
            )]
        )
        let material = SceneRenderDescriptor.MaterialPassDescriptor(
            id: "\(materialPath)#0",
            materialPath: materialPath,
            materialRawSHA256: options.materialHash,
            passIndex: 0,
            shaderPath: shaderIdentity,
            texturePaths: [],
            textureSlots: [],
            userTextureInputs: [],
            combos: [:],
            constantShaderValues: [:],
            userShaderValues: options.materialUserValue ? ["u_alpha": "fixture"] : [:],
            blending: options.blending,
            depthTest: "disabled",
            depthWrite: "disabled",
            cullMode: "nocull",
            alphaWriting: options.alphaWriting
        )
        return .init(
            layers: [.init(
                id: layerID,
                contentKind: options.contentKind,
                utilityLayer: options.utility ? .init(kind: .fullscreen) : nil,
                childLayerIDs: options.children,
                dependencyLayerIDs: options.dependencies,
                effects: [effect]
            )],
            materialPasses: [material],
            effectDefinitions: [definition(options)]
        )
    }

    static func graph(binding: Bool = false, blocker: Bool = false) -> Graph {
        let key = Graph.EffectKey(
            layerID: layerID,
            effectIndex: 0,
            descriptorID: descriptorID
        )
        let input = Graph.TextureIdentity(
            kind: .layerSource, layerID: layerID, effect: nil, name: nil
        )
        let output = Graph.TextureIdentity(
            kind: .effectOutput, layerID: layerID, effect: key, name: nil
        )
        return .init(
            layerID: layerID,
            effects: [.init(
                key: key,
                definitionPath: definitionPath,
                input: input,
                output: output,
                nodeIndices: [0]
            )],
            renderTargets: [],
            nodes: [.init(
                nodeIndex: 0,
                effect: key,
                definitionPassIndex: 0,
                materialOrdinal: 0,
                instancePassIndex: 0,
                kind: .material,
                materialPath: materialPath,
                materialPassID: "\(materialPath)#0",
                target: output,
                bindings: binding ? [.init(
                    slot: 0,
                    authoredName: nil,
                    texture: input,
                    conditions: nil
                )] : [],
                commandSource: nil,
                commandTarget: nil,
                compose: nil,
                conditions: nil
            )],
            finalOutput: output,
            blockers: blocker ? [.init(
                effect: key,
                definitionPassIndex: 0,
                reason: .unsupportedCondition,
                detail: "fixture"
            )] : []
        )
    }

    private struct CanonicalPayload: Encodable {
        let identity: String
        let sourceKind: SceneShaderContract.SourceKind
        let stages: [SceneShaderContract.Stage]
        let diagnostics: [SceneShaderContract.Diagnostic]
    }

    static func contract(fragmentHash: String = Harness.fragmentHash) -> SceneShaderContract {
        let stages = [
            SceneShaderContract.Stage(
                kind: .vertex,
                relativePath: "shaders/\(shaderIdentity).vert",
                source: "// project-owned fixture vertex\n",
                rawSHA256: vertexHash,
                includes: [], annotations: [], declarations: []
            ),
            SceneShaderContract.Stage(
                kind: .fragment,
                relativePath: "shaders/\(shaderIdentity).frag",
                source: "// project-owned fixture fragment\n",
                rawSHA256: fragmentHash,
                includes: [], annotations: [], declarations: []
            ),
        ]
        let payload = CanonicalPayload(
            identity: shaderIdentity,
            sourceKind: .authoredSource,
            stages: stages,
            diagnostics: []
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try! encoder.encode(payload)
        let canonical = SHA256.hash(data: data).map {
            String(format: "%02x", $0)
        }.joined()
        return .init(
            identity: shaderIdentity,
            sourceKind: .authoredSource,
            stages: stages,
            diagnostics: [],
            canonicalSHA256: canonical
        )
    }

    static func plan(
        _ options: Options = .init(),
        contract shader: SceneShaderContract = contract(),
        binding: Bool = false,
        blocker: Bool = false
    ) -> SceneColorGradingExecutionPlan? {
        SceneAuthoredColorGradingPlanner.plan(
            graph: graph(binding: binding, blocker: blocker),
            descriptor: descriptor(options),
            shaderContracts: [shader]
        )
    }

    static func main() throws {
        let accepted = plan()
        var ignored = Options()
        ignored.brightness = -0.8
        ignored.contrast = 0.9
        let ignoredPlan = plan(ignored)

        var wrongDefinition = Options()
        wrongDefinition.definitionHash = String(repeating: "0", count: 64)
        var wrongMaterial = Options()
        wrongMaterial.materialHash = String(repeating: "0", count: 64)
        var definitionExtra = Options(); definitionExtra.definitionExtra = true
        var wrongCombo = Options(); wrongCombo.combos = ["TOOLS": 1]
        var extraCombo = Options(); extraCombo.combos["MASK"] = 0
        var texture = Options(); texture.texture = true
        var materialUser = Options(); materialUser.materialUserValue = true
        var state = Options(); state.blending = "additive"
        var alphaWriting = Options(); alphaWriting.alphaWriting = "enabled"
        var kind = Options(); kind.contentKind = "image"
        var noUtility = Options(); noUtility.utility = false
        var children = Options(); children.children = [2]
        var dependencies = Options(); dependencies.dependencies = [2]
        var opacity = Options(); opacity.opacity = 1.01
        var luminance = Options(); luminance.luminance = -.infinity
        var influence = Options(); influence.influence = [1, .nan, 1]
        var bindingValue = Options(); bindingValue.boundKey = "vibrance"
        var extraConstant = Options(); extraConstant.extraConstant = true
        var missingConstant = Options(); missingConstant.omitConstant = "Contrast"
        var hidden = Options(); hidden.visible = false

        let rejectedOptions = [
            wrongDefinition, wrongMaterial, definitionExtra, wrongCombo, extraCombo,
            texture, materialUser, state, alphaWriting, kind, noUtility, children,
            dependencies, opacity, luminance, influence, bindingValue,
            extraConstant, missingConstant, hidden,
        ].allSatisfy { plan($0) == nil }
        let wrongShader = contract(fragmentHash: String(repeating: "0", count: 64))

        let result: [String: Any] = [
            "accepted": accepted != nil,
            "parameters": accepted.map {
                [$0.luminance, $0.saturation, $0.vibrance, $0.opacity]
            } ?? [],
            "influence": accepted.map {
                [$0.channelInfluence.x, $0.channelInfluence.y, $0.channelInfluence.z]
            } ?? [],
            "ignoredFieldsDoNotEnterPlan": accepted != nil && ignoredPlan != nil
                && accepted!.luminance == ignoredPlan!.luminance
                && accepted!.saturation == ignoredPlan!.saturation
                && accepted!.vibrance == ignoredPlan!.vibrance
                && accepted!.opacity == ignoredPlan!.opacity
                && accepted!.channelInfluence == ignoredPlan!.channelInfluence,
            "strictOptionsRejected": rejectedOptions,
            "wrongShaderRejected": plan(.init(), contract: wrongShader) == nil,
            "bindingRejected": plan(.init(), binding: true) == nil,
            "blockerRejected": plan(.init(), blocker: true) == nil,
        ]
        let data = try JSONSerialization.data(
            withJSONObject: result,
            options: [.sortedKeys]
        )
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class SceneColorGradingPlannerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-color-grading-planner-"
        )
        root = Path(cls.temporary_directory.name)
        harness = root / "Harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        binary = root / "scene-color-grading-planner"
        compilation = subprocess.run(
            [
                "xcrun",
                "--sdk",
                "macosx",
                "swiftc",
                *(str(path) for path in SWIFT_SOURCES),
                str(harness),
                "-o",
                str(binary),
            ],
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)
        completed = subprocess.run(
            [str(binary)],
            check=True,
            capture_output=True,
            text=True,
        )
        cls.result = json.loads(completed.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_exact_tools_two_profile_is_admitted(self) -> None:
        self.assertTrue(self.result["accepted"])
        for actual, expected in zip(
            self.result["parameters"], [-0.01, 0.2, 0.31, 1]
        ):
            self.assertAlmostEqual(actual, expected, places=6)
        self.assertEqual(self.result["influence"], [1, 1, 1])

    def test_inactive_brightness_and_contrast_are_not_consumed(self) -> None:
        self.assertTrue(self.result["ignoredFieldsDoNotEnterPlan"])

    def test_unknown_or_mutated_contracts_fail_closed(self) -> None:
        self.assertTrue(self.result["strictOptionsRejected"])
        self.assertTrue(self.result["wrongShaderRejected"])
        self.assertTrue(self.result["bindingRejected"])
        self.assertTrue(self.result["blockerRejected"])


if __name__ == "__main__":
    unittest.main()
