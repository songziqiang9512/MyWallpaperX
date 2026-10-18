#!/usr/bin/env python3

"""Executable shared graph admission coverage for stock blurred/current composite."""

from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
GRAPH_ADMISSION_SOURCE = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneResolvedMaterialPreviousBlurredCompositeGraphAdmission.swift"
)
DEDICATED_PLANNER_SOURCE = (
    SCENE_ROOT / "RenderGraph/SceneAuthoredStandardBlurPlanner.swift"
)
OWNER_ADMISSION_SOURCE = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneResolvedMaterialPreviousBlurredCompositeOwnerAdmission.swift"
)
SWIFT_SOURCES = [
    SCENE_ROOT / "Format/SceneJSONValue.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Graph/SceneAuthoredEffectRenderPlan.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneAuthoredMaterialResolver.swift",
    GRAPH_ADMISSION_SOURCE,
]


HARNESS = r'''
import Foundation

struct SceneDocument {
    struct ShaderValue {
        let valueKind: String
        let userBinding: String?
        let components: [Double]?

        init(
            valueKind: String = "vector",
            userBinding: String? = nil,
            components: [Double]?
        ) {
            self.valueKind = valueKind
            self.userBinding = userBinding
            self.components = components
        }
    }
}

struct SceneEffectTextureInput {
    let name: String
}

struct SceneRenderDescriptor {
    struct EffectDescriptor {
        struct PassDescriptor {
            let passIndex: Int
            let textureSlots: [String?]
            let userTextureInputs: [SceneEffectTextureInput?]
            let combos: [String: Int]
            let constantShaderValues: [String: SceneDocument.ShaderValue]
        }

        let id: String
        let passes: [PassDescriptor]
    }

    struct Layer {
        let id: Int
        let contentKind: String
        let effects: [EffectDescriptor]
    }

    struct MaterialPassDescriptor {
        let id: String
        let materialPath: String
        let shaderPath: String?
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
}

@main
enum Harness {
    typealias Graph = SceneAuthoredEffectRenderPlan

    enum Fixture: String, CaseIterable {
        case stock
        case workshopNamespaced
        case workshopWrongNamespace
        case stockDefinitionNamespacedShader
        case maskedStock
        case wrongTarget
        case wrongTargetExtent
        case wrongBinding
        case kernel
        case kernelZero
        case kernelOne
        case kernelMixedVertical
        case kernelNegative
        case kernelTwo
        case kernelUnknown
        case kernelOneWrongTarget
        case tintedStaticComposite
        case dynamicComposite
        case maskWithoutAsset
        case maskFromMaterial
        case renamedResources
        case largeTwelve, largeThirtyTwo, unrelatedLargerScale, anisotropicScale
        case oldUpperBoundary, aboveOldUpperBoundary
        case zeroScale, negativeScale, belowMinimumScale
        case floatOverflowScale, largestFiniteFloatScale, nonfiniteScale
        case mismatchedScales, wrongScaleShape, wrongState, wrongTargetFormat
        case zeroHorizontalLane, zeroVerticalLane, scalarZero, equivalentZeroAxis
        case smallestPositiveFloat, positiveFloatUnderflow, negativeZeroScale, mixedNegativeZero
        case negativeFirstLane, negativeSecondLane, negativeFloatUnderflow
        case nanFirstLane, nanSecondLane, infiniteFirstLane, infiniteSecondLane, negativeInfinityScale
        case floatOverflowFirstLane, floatOverflowSecondLane
        case emptyScale, missingScale, missingFirstPassScale, missingScaleComponents
        case mismatchedZeroAxes, zeroTargetExtent, zeroSecondTargetExtent
        case renamedZeroAxisResources

        var usesRenamedResources: Bool {
            self == .renamedResources || self == .renamedZeroAxisResources
        }
    }

    static let layerID = 530
    static let effectKey = Graph.EffectKey(
        layerID: layerID,
        effectIndex: 0,
        descriptorID: "530#effect#0"
    )
    static let source = Graph.TextureIdentity(
        kind: .layerSource,
        layerID: layerID,
        effect: nil,
        name: nil
    )
    static let output = Graph.TextureIdentity(
        kind: .effectOutput,
        layerID: layerID,
        effect: effectKey,
        name: nil
    )
    static let quarterA = framebuffer("_rt_QuarterCompoBuffer1")
    static let quarterB = framebuffer("_rt_QuarterCompoBuffer2")

    static func framebuffer(_ name: String) -> Graph.TextureIdentity {
        .init(
            kind: .framebuffer,
            layerID: layerID,
            effect: effectKey,
            name: name
        )
    }

    static func binding(
        slot: Int,
        name: String,
        texture: Graph.TextureIdentity
    ) -> Graph.Binding {
        .init(
            slot: slot,
            authoredName: name,
            texture: texture,
            conditions: nil
        )
    }

    static func node(
        ordinal: Int,
        target: Graph.TextureIdentity,
        bindings: [Graph.Binding],
        fixture: Fixture = .stock
    ) -> Graph.Node {
        let materialPaths = [
            "materials/effects/blur_downsample4.json",
            "materials/effects/blur_gaussian_x.json",
            "materials/effects/blur_gaussian_y.json",
            "materials/effects/blur_combine.json",
        ]
        let materialPath = fixture.usesRenamedResources
            ? "materials/independent/store-\(ordinal).json" : materialPaths[ordinal]
        return .init(
            nodeIndex: ordinal,
            effect: effectKey,
            definitionPassIndex: ordinal,
            materialOrdinal: ordinal,
            instancePassIndex: ordinal,
            kind: .material,
            materialPath: materialPath,
            materialPassID: "\(materialPath)#0",
            target: target,
            bindings: bindings,
            commandSource: nil,
            commandTarget: nil,
            compose: nil,
            conditions: nil
        )
    }

    static func graph(_ fixture: Fixture) -> Graph {
        let quarterA = fixture.usesRenamedResources ? framebuffer("independent-left") : Self.quarterA
        let quarterB = fixture.usesRenamedResources ? framebuffer("independent-right") : Self.quarterB
        let verticalTarget = [Fixture.wrongTarget, .kernelOneWrongTarget]
            .contains(fixture) ? quarterB : quarterA
        let previousSlot = fixture == .wrongBinding ? 1 : 2
        let nodes = [
            node(
                ordinal: 0,
                target: quarterA,
                bindings: [binding(slot: 0, name: "previous", texture: source)], fixture: fixture
            ),
            node(
                ordinal: 1,
                target: quarterB,
                bindings: [
                    binding(
                        slot: 0,
                        name: quarterA.name!,
                        texture: quarterA
                    ),
                ], fixture: fixture
            ),
            node(
                ordinal: 2,
                target: verticalTarget,
                bindings: [
                    binding(
                        slot: 0,
                        name: quarterB.name!,
                        texture: quarterB
                    ),
                ], fixture: fixture
            ),
            node(
                ordinal: 3,
                target: output,
                bindings: [
                    binding(
                        slot: 0,
                        name: quarterA.name!,
                        texture: quarterA
                    ),
                    binding(
                        slot: previousSlot,
                        name: "previous",
                        texture: source
                    ),
                ], fixture: fixture
            ),
        ]
        let effect = Graph.Effect(
            key: effectKey,
            definitionPath: fixture.usesRenamedResources ? "independent/soft-result.json" : fixture == .workshopNamespaced
                || fixture == .workshopWrongNamespace
                ? "effects/workshop/3260400126/blur/effect.json"
                : "effects/blur/effect.json",
            input: source,
            output: output,
            nodeIndices: nodes.map(\.nodeIndex)
        )
        return .init(
            layerID: layerID,
            effects: [effect],
            renderTargets: [quarterA, quarterB].enumerated().map { index, texture in
                .init(
                    texture: texture,
                    extent: .init(
                        kind: .scale,
                        first: fixture == .zeroTargetExtent && index == 0 ? 0
                            : fixture == .wrongTargetExtent && index == 0 ? 2 : 4,
                        second: fixture == .zeroSecondTargetExtent && index == 0 ? 0 : nil
                    ),
                    format: fixture == .wrongTargetFormat ? "rg8" : "rgba_backbuffer",
                    declaredUnique: false,
                    clear: nil,
                    uvs: nil,
                    conditions: nil
                )
            },
            nodes: nodes,
            finalOutput: output,
            blockers: []
        )
    }

    static func effectPasses(
        _ fixture: Fixture
    ) -> [SceneRenderDescriptor.EffectDescriptor.PassDescriptor] {
        let components: [Double]? = switch fixture {
        case .largeTwelve: [12, 12]
        case .largeThirtyTwo: [32, 32]
        case .unrelatedLargerScale: [73, 73]
        case .anisotropicScale: [12, 32]
        case .oldUpperBoundary: [2, 2]
        case .aboveOldUpperBoundary: [2.1, 2.1]
        case .zeroScale: [0, 0]
        case .zeroHorizontalLane, .renamedZeroAxisResources: [0.99, 0]
        case .zeroVerticalLane, .mismatchedZeroAxes: [0, 0.99]
        case .scalarZero: [0]
        case .equivalentZeroAxis: [0.33 * 3, 1 - 1]
        case .smallestPositiveFloat: [Double(Float.leastNonzeroMagnitude), 0.99]
        case .positiveFloatUnderflow: [Double.leastNonzeroMagnitude, 0.99]
        case .negativeZeroScale: [-0.0, -0.0]
        case .mixedNegativeZero: [0.99, -0.0]
        case .negativeFirstLane: [-0.01, 0.99]
        case .negativeSecondLane: [0.99, -0.01]
        case .negativeFloatUnderflow: [-Double.leastNonzeroMagnitude, 0.99]
        case .nanFirstLane: [.nan, 0.99]
        case .nanSecondLane: [0.99, .nan]
        case .infiniteFirstLane: [.infinity, 0.99]
        case .infiniteSecondLane: [0.99, .infinity]
        case .negativeInfinityScale: [-.infinity, 0.99]
        case .floatOverflowFirstLane: [1e40, 0.99]
        case .floatOverflowSecondLane: [0.99, 1e40]
        case .emptyScale: []
        case .missingScaleComponents: nil
        case .negativeScale: [-1, -1]
        case .belowMinimumScale: [0.001, 0.001]
        case .floatOverflowScale: [1e40, 1e40]
        case .largestFiniteFloatScale: [Double(Float.greatestFiniteMagnitude), Double(Float.greatestFiniteMagnitude)]
        case .nonfiniteScale: [.nan, .infinity]
        case .wrongScaleShape: [1, 1, 1]
        default: [0.6, 0.6]
        }
        let plainAuthored: Bool = switch fixture {
        case .largeTwelve, .largeThirtyTwo, .unrelatedLargerScale, .anisotropicScale, .oldUpperBoundary,
             .aboveOldUpperBoundary, .zeroScale, .negativeScale, .belowMinimumScale,
             .floatOverflowScale, .largestFiniteFloatScale, .nonfiniteScale,
             .wrongScaleShape, .zeroHorizontalLane, .zeroVerticalLane, .scalarZero,
             .equivalentZeroAxis, .smallestPositiveFloat, .positiveFloatUnderflow,
             .negativeZeroScale, .mixedNegativeZero, .negativeFirstLane, .negativeSecondLane,
             .negativeFloatUnderflow, .nanFirstLane, .nanSecondLane, .infiniteFirstLane,
             .infiniteSecondLane, .negativeInfinityScale, .floatOverflowFirstLane,
             .floatOverflowSecondLane, .emptyScale, .missingScaleComponents,
             .mismatchedZeroAxes, .renamedZeroAxisResources: true
        default: false
        }
        let scale = SceneDocument.ShaderValue(valueKind: fixture == .scalarZero ? "scalar" : plainAuthored ? "vector" : "binding",
            userBinding: plainAuthored ? nil : "newproperty", components: components)
        let secondScale = switch fixture {
        case .mismatchedScales: SceneDocument.ShaderValue(components: [0.7, 0.7])
        case .mismatchedZeroAxes: SceneDocument.ShaderValue(components: [0.99, 0])
        default: scale
        }
        let maskIsEnabled = [
            Fixture.maskedStock,
            .maskWithoutAsset,
            .maskFromMaterial,
        ].contains(fixture)
        let instanceMask = fixture == .maskedStock ? "masks/blur-mask" : nil
        let kernelPair: (Int, Int)? = switch fixture {
        case .kernel: (1, 0)
        case .kernelZero: (0, 0)
        case .kernelOne, .kernelOneWrongTarget: (1, 1)
        case .kernelMixedVertical: (0, 1)
        case .kernelNegative: (-1, -1)
        case .kernelTwo: (2, 2)
        case .kernelUnknown: (7, 7)
        default: nil
        }
        return [
            .init(
                passIndex: 0,
                textureSlots: [],
                userTextureInputs: [],
                combos: [:],
                constantShaderValues: [:]
            ),
            .init(
                passIndex: 1,
                textureSlots: [],
                userTextureInputs: [],
                combos: kernelPair.map { ["KERNEL": $0.0] } ?? [:],
                constantShaderValues: [Fixture.missingScale, .missingFirstPassScale].contains(fixture)
                    ? [:] : ["scale": secondScale]
            ),
            .init(
                passIndex: 2,
                textureSlots: [],
                userTextureInputs: [],
                combos: kernelPair.map { ["KERNEL": $0.1] } ?? [:],
                constantShaderValues: fixture == .missingScale ? [:] : ["scale": scale]
            ),
            .init(
                passIndex: 3,
                textureSlots: [nil, instanceMask],
                userTextureInputs: [],
                combos: maskIsEnabled ? ["MASK": 1] : [:],
                constantShaderValues: {
                    if fixture == .tintedStaticComposite {
                        return [
                            "compositecolor": .init(components: [0.5, 1, 1]),
                        ]
                    }
                    if fixture == .dynamicComposite {
                        return [
                            "compositecolor": .init(
                                valueKind: "binding",
                                userBinding: "colorproperty",
                                components: [0.5, 1, 1]
                            ),
                        ]
                    }
                    return [:]
                }()
            ),
        ]
    }

    static func material(
        name: String,
        shader: String,
        combos: [String: Int] = [:],
        textureSlots: [String?] = [],
        fixture: Fixture = .stock,
        ordinal: Int = 0
    ) -> SceneRenderDescriptor.MaterialPassDescriptor {
        .init(
            id: fixture.usesRenamedResources ? "materials/independent/store-\(ordinal).json#0" : "materials/effects/\(name).json#0",
            materialPath: fixture.usesRenamedResources ? "materials/independent/store-\(ordinal).json" : "materials/effects/\(name).json",
            shaderPath: shader,
            textureSlots: textureSlots,
            userTextureInputs: [],
            combos: combos,
            constantShaderValues: [:],
            userShaderValues: [:],
            blending: fixture == .wrongState ? "unrecognized" : "normal",
            depthTest: "disabled",
            depthWrite: "disabled",
            cullMode: "nocull",
            alphaWriting: nil
        )
    }

    static func descriptor(_ fixture: Fixture) -> SceneRenderDescriptor {
        let materialMask: [String?] = fixture == .maskFromMaterial
            ? [nil, "masks/material-owned-mask"]
            : []
        let shaderNamespace: String? = switch fixture {
        case .workshopNamespaced:
            "workshop/3260400126"
        case .workshopWrongNamespace:
            "workshop/other"
        case .stockDefinitionNamespacedShader:
            "workshop/3260400126"
        default:
            nil
        }
        func shader(_ basename: String) -> String {
            if fixture.usesRenamedResources {
                return "shaders/independent/resource-\(basename.count)"
            }
            if let shaderNamespace {
                return "\(shaderNamespace)/effects/\(basename)"
            }
            return "effects/\(basename)"
        }
        return .init(
            layers: [
                .init(
                    id: layerID,
                    contentKind: "composition",
                    effects: [
                .init(
                    id: effectKey.descriptorID,
                    passes: effectPasses(fixture)
                ),
                    ]
                ),
            ],
            materialPasses: [
                material(
                    name: "blur_downsample4",
                    shader: shader("blur_downsample4"), fixture: fixture, ordinal: 0
                ),
                material(
                    name: "blur_gaussian_x",
                    shader: shader("blur_gaussian"), fixture: fixture, ordinal: 1
                ),
                material(
                    name: "blur_gaussian_y",
                    shader: shader("blur_gaussian"),
                    combos: ["VERTICAL": 1], fixture: fixture, ordinal: 2
                ),
                material(
                    name: "blur_combine",
                    shader: shader("blur_combine"),
                    textureSlots: materialMask, fixture: fixture, ordinal: 3
                ),
            ]
        )
    }

    static func main() throws {
        var result: [String: Bool] = [:]
        for fixture in Fixture.allCases {
            result[fixture.rawValue] =
                SceneResolvedMaterialPreviousBlurredCompositeGraphAdmission
                    .accepts(
                        graph: graph(fixture),
                        descriptor: descriptor(fixture),
                        inputRole: .layerSource
                    )
        }
        let data = try JSONSerialization.data(
            withJSONObject: result,
            options: [.sortedKeys]
        )
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class SceneResolvedMaterialPreviousBlurredCompositeGraphAdmissionTests(
    unittest.TestCase
):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-scene-previous-blurred-graph-admission-"
        )
        root = Path(cls.temporary_directory.name)
        harness = root / "Harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        cls.binary = root / "graph-admission"
        compilation = subprocess.run(
            [
                "xcrun",
                "--sdk",
                "macosx",
                "swiftc",
                *(str(source) for source in SWIFT_SOURCES),
                str(harness),
                "-o",
                str(cls.binary),
            ],
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)
        completed = subprocess.run(
            [str(cls.binary)],
            check=True,
            capture_output=True,
            text=True,
        )
        cls.result = json.loads(completed.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_stock_four_node_two_fbo_graph_is_admitted(self) -> None:
        self.assertTrue(self.result["stock"])
        self.assertTrue(self.result["maskedStock"])

    def test_resource_names_do_not_grant_or_revoke_graph_admission(self) -> None:
        self.assertTrue(self.result["workshopNamespaced"])
        self.assertTrue(self.result["workshopWrongNamespace"])
        self.assertTrue(self.result["stockDefinitionNamespacedShader"])
        self.assertTrue(self.result["renamedResources"])

    def test_scale_amount_is_not_limited_to_editor_upper_boundary(self) -> None:
        for fixture in ("oldUpperBoundary", "aboveOldUpperBoundary", "largeTwelve",
                        "largeThirtyTwo", "unrelatedLargerScale", "largestFiniteFloatScale", "anisotropicScale"):
            with self.subTest(fixture=fixture):
                self.assertTrue(self.result[fixture])

    def test_zero_sampling_axes_are_values_not_target_extents(self) -> None:
        for fixture in ("zeroHorizontalLane", "zeroVerticalLane", "zeroScale", "scalarZero",
                        "negativeZeroScale", "mixedNegativeZero", "equivalentZeroAxis",
                        "renamedZeroAxisResources"):
            with self.subTest(fixture=fixture):
                self.assertTrue(self.result[fixture])

    def test_small_positive_scale_and_float_underflow_remain_admitted(self) -> None:
        for fixture in ("belowMinimumScale", "smallestPositiveFloat", "positiveFloatUnderflow"):
            with self.subTest(fixture=fixture):
                self.assertTrue(self.result[fixture])

    def test_scale_numeric_and_whole_stage_neighbors_remain_rejected(self) -> None:
        for fixture in ("negativeScale", "negativeFirstLane", "negativeSecondLane",
                        "negativeFloatUnderflow", "floatOverflowScale", "floatOverflowFirstLane",
                        "floatOverflowSecondLane", "nonfiniteScale", "nanFirstLane", "nanSecondLane",
                        "infiniteFirstLane", "infiniteSecondLane", "negativeInfinityScale",
                        "wrongScaleShape", "emptyScale", "missingScale", "missingFirstPassScale",
                        "missingScaleComponents", "mismatchedScales", "mismatchedZeroAxes",
                        "wrongState", "wrongTargetFormat"):
            with self.subTest(fixture=fixture):
                self.assertFalse(self.result[fixture])

    def test_target_and_binding_contracts_reject_mismatched_graphs(self) -> None:
        self.assertFalse(self.result["wrongTarget"])
        self.assertFalse(self.result["wrongTargetExtent"])
        self.assertFalse(self.result["zeroTargetExtent"])
        self.assertFalse(self.result["zeroSecondTargetExtent"])
        self.assertFalse(self.result["wrongBinding"])

    def test_matching_kernel_zero_and_one_preserve_the_whole_graph_contract(self) -> None:
        self.assertTrue(self.result["stock"])
        self.assertTrue(self.result["kernelZero"])
        self.assertTrue(self.result["kernelOne"])
        self.assertFalse(self.result["kernelOneWrongTarget"])

    def test_mixed_and_unsupported_kernel_pairs_are_rejected(self) -> None:
        for fixture in ("kernelMixedVertical", "kernelNegative", "kernelTwo", "kernelUnknown"):
            with self.subTest(fixture=fixture):
                self.assertFalse(self.result[fixture])

    def test_static_tint_is_admitted_but_dynamic_or_malformed_shape_is_not(self) -> None:
        self.assertFalse(self.result["kernel"])
        self.assertTrue(self.result["tintedStaticComposite"])
        self.assertFalse(self.result["dynamicComposite"])
        self.assertFalse(self.result["maskWithoutAsset"])
        self.assertFalse(self.result["maskFromMaterial"])

    def test_shared_admission_is_independent_from_incumbent_planner(
        self,
    ) -> None:
        source = GRAPH_ADMISSION_SOURCE.read_text(encoding="utf-8")
        owner_source = OWNER_ADMISSION_SOURCE.read_text(encoding="utf-8")
        self.assertIn(
            "SceneResolvedMaterialPreviousBlurredCompositeGraphAdmission",
            source,
        )
        self.assertNotIn("SceneAuthoredStandardBlurPlanner", source)
        self.assertIn(
            "SceneResolvedMaterialPreviousBlurredCompositeGraphAdmission",
            owner_source,
        )
        self.assertNotIn("SceneAuthoredStandardBlurPlanner.plan(", owner_source)
        self.assertNotIn(DEDICATED_PLANNER_SOURCE, SWIFT_SOURCES)
        self.assertFalse(DEDICATED_PLANNER_SOURCE.exists())


if __name__ == "__main__":
    unittest.main()
