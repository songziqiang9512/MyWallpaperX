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
    SCENE_ROOT
    / "RenderGraph/SceneResolvedMaterialUnitPreviousBlurredCompositeGraphAdmission.swift"
)
DEDICATED_PLANNER_SOURCE = (
    SCENE_ROOT / "RenderGraph/SceneAuthoredStandardBlurPlanner.swift"
)
OWNER_ADMISSION_SOURCE = (
    SCENE_ROOT
    / "RenderGraph/SceneResolvedMaterialUnitPreviousBlurredCompositeOwnerAdmission.swift"
)
SWIFT_SOURCES = [
    SCENE_ROOT / "Format/SceneJSONValue.swift",
    SCENE_ROOT / "RenderGraph/AuthoredGraph/SceneAuthoredEffectRenderPlan.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredMaterialResolver.swift",
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
        case maskedStock
        case wrongTarget
        case wrongTargetExtent
        case wrongBinding
        case kernel
        case nonUnitComposite
        case maskWithoutAsset
        case maskFromMaterial
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
        bindings: [Graph.Binding]
    ) -> Graph.Node {
        let materialPaths = [
            "materials/effects/blur_downsample4.json",
            "materials/effects/blur_gaussian_x.json",
            "materials/effects/blur_gaussian_y.json",
            "materials/effects/blur_combine.json",
        ]
        let materialPath = materialPaths[ordinal]
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
        let verticalTarget = fixture == .wrongTarget ? quarterB : quarterA
        let previousSlot = fixture == .wrongBinding ? 1 : 2
        let nodes = [
            node(
                ordinal: 0,
                target: quarterA,
                bindings: [binding(slot: 0, name: "previous", texture: source)]
            ),
            node(
                ordinal: 1,
                target: quarterB,
                bindings: [
                    binding(
                        slot: 0,
                        name: "_rt_QuarterCompoBuffer1",
                        texture: quarterA
                    ),
                ]
            ),
            node(
                ordinal: 2,
                target: verticalTarget,
                bindings: [
                    binding(
                        slot: 0,
                        name: "_rt_QuarterCompoBuffer2",
                        texture: quarterB
                    ),
                ]
            ),
            node(
                ordinal: 3,
                target: output,
                bindings: [
                    binding(
                        slot: 0,
                        name: "_rt_QuarterCompoBuffer1",
                        texture: quarterA
                    ),
                    binding(
                        slot: previousSlot,
                        name: "previous",
                        texture: source
                    ),
                ]
            ),
        ]
        let effect = Graph.Effect(
            key: effectKey,
            definitionPath: "effects/blur/effect.json",
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
                        first: fixture == .wrongTargetExtent && index == 0 ? 2 : 4,
                        second: nil
                    ),
                    format: "rgba_backbuffer",
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
        let scale = SceneDocument.ShaderValue(
            valueKind: "binding",
            userBinding: "newproperty",
            components: [0.6, 0.6]
        )
        let maskIsEnabled = [
            Fixture.maskedStock,
            .maskWithoutAsset,
            .maskFromMaterial,
        ].contains(fixture)
        let instanceMask = fixture == .maskedStock ? "masks/blur-mask" : nil
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
                combos: fixture == .kernel ? ["KERNEL": 1] : [:],
                constantShaderValues: ["scale": scale]
            ),
            .init(
                passIndex: 2,
                textureSlots: [],
                userTextureInputs: [],
                combos: [:],
                constantShaderValues: ["scale": scale]
            ),
            .init(
                passIndex: 3,
                textureSlots: [nil, instanceMask],
                userTextureInputs: [],
                combos: maskIsEnabled ? ["MASK": 1] : [:],
                constantShaderValues: fixture == .nonUnitComposite
                    ? [
                        "compositecolor": .init(components: [0.5, 1, 1]),
                    ]
                    : [:]
            ),
        ]
    }

    static func material(
        name: String,
        shader: String,
        combos: [String: Int] = [:],
        textureSlots: [String?] = []
    ) -> SceneRenderDescriptor.MaterialPassDescriptor {
        .init(
            id: "materials/effects/\(name).json#0",
            materialPath: "materials/effects/\(name).json",
            shaderPath: shader,
            textureSlots: textureSlots,
            userTextureInputs: [],
            combos: combos,
            constantShaderValues: [:],
            userShaderValues: [:],
            blending: "normal",
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
                    shader: "effects/blur_downsample4"
                ),
                material(
                    name: "blur_gaussian_x",
                    shader: "effects/blur_gaussian"
                ),
                material(
                    name: "blur_gaussian_y",
                    shader: "effects/blur_gaussian",
                    combos: ["VERTICAL": 1]
                ),
                material(
                    name: "blur_combine",
                    shader: "effects/blur_combine",
                    textureSlots: materialMask
                ),
            ]
        )
    }

    static func main() throws {
        var result: [String: Bool] = [:]
        for fixture in Fixture.allCases {
            result[fixture.rawValue] =
                SceneResolvedMaterialUnitPreviousBlurredCompositeGraphAdmission
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


class SceneResolvedMaterialUnitPreviousBlurredCompositeGraphAdmissionTests(
    unittest.TestCase
):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-scene-unit-previous-blurred-graph-admission-"
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

    def test_target_and_binding_contracts_reject_exact_graph_unit(self) -> None:
        self.assertFalse(self.result["wrongTarget"])
        self.assertFalse(self.result["wrongTargetExtent"])
        self.assertFalse(self.result["wrongBinding"])

    def test_material_and_mask_contracts_reject_exact_graph_unit(self) -> None:
        self.assertFalse(self.result["kernel"])
        self.assertFalse(self.result["nonUnitComposite"])
        self.assertFalse(self.result["maskWithoutAsset"])
        self.assertFalse(self.result["maskFromMaterial"])

    def test_shared_admission_is_independent_from_incumbent_planner(
        self,
    ) -> None:
        source = GRAPH_ADMISSION_SOURCE.read_text(encoding="utf-8")
        owner_source = OWNER_ADMISSION_SOURCE.read_text(encoding="utf-8")
        self.assertIn(
            "SceneResolvedMaterialUnitPreviousBlurredCompositeGraphAdmission",
            source,
        )
        self.assertNotIn("SceneAuthoredStandardBlurPlanner", source)
        self.assertIn(
            "SceneResolvedMaterialUnitPreviousBlurredCompositeGraphAdmission",
            owner_source,
        )
        self.assertNotIn("SceneAuthoredStandardBlurPlanner.plan(", owner_source)
        self.assertNotIn(DEDICATED_PLANNER_SOURCE, SWIFT_SOURCES)
        self.assertFalse(DEDICATED_PLANNER_SOURCE.exists())


if __name__ == "__main__":
    unittest.main()
