#!/usr/bin/env python3
"""Foliage Sway stock profile 的可选遮罩与 fail-closed 准入测试。"""

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
STOCK_EFFECT_ROOT = (
    REPOSITORY_ROOT
    / "MyWallpaperX/Resources/SceneStockAssets.bundle/assets/effects/foliagesway"
)
SWIFT_SOURCES = [
    SOURCE_ROOT / "Format/SceneJSONValue.swift",
    SOURCE_ROOT / "Rendering/SceneUtilityLayer.swift",
    SOURCE_ROOT / "RenderGraph/SceneEffectDefinition.swift",
    SOURCE_ROOT / "RenderGraph/AuthoredGraph/SceneAuthoredEffectRenderPlan.swift",
    SOURCE_ROOT / "RenderGraph/SceneAuthoredMaterialResolver.swift",
    SOURCE_ROOT / "RenderGraph/ShaderContract/SceneShaderSourceGraph.swift",
    SOURCE_ROOT / "RenderGraph/ShaderContract/SceneShaderContract.swift",
    SOURCE_ROOT / "Resources/SceneShaderSourceGraphBuilder.swift",
    SOURCE_ROOT / "Resources/SceneShaderSourceResolver.swift",
    SOURCE_ROOT / "Resources/SceneResourceView.swift",
    SOURCE_ROOT / "Resources/SceneResourceIndex.swift",
    SOURCE_ROOT / "RenderGraph/ShaderContract/SceneShaderContractLoader.swift",
    SOURCE_ROOT / "RenderGraph/ShaderContract/SceneShaderContractLoader+SourceGraph.swift",
    SOURCE_ROOT / "RenderGraph/SceneEffectMaskSemantics.swift",
    SOURCE_ROOT / "Effects/SceneFoliageSwayRuntimePlan.swift",
    SOURCE_ROOT / "RenderGraph/SceneFoliageSwayShaderProfile.swift",
    SOURCE_ROOT / "RenderGraph/SceneAuthoredFoliageSwayPlanner.swift",
]


HARNESS = r'''
import Foundation

struct SceneDocument {
    struct ShaderValue {
        let rawValue: String
        let valueKind: String
        let userBinding: String?
        let components: [Double]?
        let timeline: String?
        let timelineDiagnostics: [String]
    }
}

struct SceneEffectTextureInput {
    let name: String
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
        }

        let id: String
        let file: String
        let visible: Bool?
        let passes: [PassDescriptor]
    }

    struct Layer {
        let id: Int
        let contentKind: String
        let effects: [EffectDescriptor]
        let utilityLayer: SceneUtilityLayer?
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
        var userShaderValues: [String: String] { [:] }
        let blending: String?
        let depthTest: String?
        let depthWrite: String?
        let cullMode: String?
        let alphaWriting: String? = nil
    }

    let layers: [Layer]
    let materialPasses: [MaterialPassDescriptor]
    let effectDefinitions: [SceneEffectDefinition]
}

@main
enum Harness {
    typealias Graph = SceneAuthoredEffectRenderPlan

    static let layerID = 20
    static let descriptorID = "20#effect#21"
    static let definitionPath = "effects/foliagesway/effect.json"
    static let materialPath = "materials/effects/foliagesway.json"
    static let materialPassID = "\(materialPath)#0"
    static let shaderIdentity = "effects/foliagesway"
    static let maskPath = "masks/foliage_mask"
    static let otherMaskPath = "masks/other_mask"
    static let noisePath = "util/noise"

    struct Options {
        var slots: [String?]
        var paths: [String]
        var combos: [String: Int]
        var constants: [String: SceneDocument.ShaderValue]

        init(
            slots: [String?] = [],
            paths: [String] = [],
            combos: [String: Int] = [:],
            constants: [String: SceneDocument.ShaderValue]? = nil
        ) {
            self.slots = slots
            self.paths = paths
            self.combos = combos
            self.constants = constants ?? Harness.stockConstants()
        }
    }

    static func value(_ component: Double) -> SceneDocument.ShaderValue {
        .init(
            rawValue: String(component),
            valueKind: "number",
            userBinding: nil,
            components: [component],
            timeline: nil,
            timelineDiagnostics: []
        )
    }

    static func stockConstants() -> [String: SceneDocument.ShaderValue] {
        [
            "phase": value(0.5),
            "power": value(1),
            "ratio": value(0.3),
            "scale": value(0.05),
            "scrolldirection": value(0),
            "speeduv": value(5),
            "strength": value(0.4),
        ]
    }

    static func descriptor(_ options: Options) -> SceneRenderDescriptor {
        let instancePass = SceneRenderDescriptor.EffectDescriptor.PassDescriptor(
            passIndex: 0,
            texturePaths: options.paths,
            textureSlots: options.slots,
            userTextureInputs: [],
            combos: options.combos,
            constantShaderValues: options.constants
        )
        let effect = SceneRenderDescriptor.EffectDescriptor(
            id: descriptorID,
            file: definitionPath,
            visible: true,
            passes: [instancePass]
        )
        let material = SceneRenderDescriptor.MaterialPassDescriptor(
            id: materialPassID,
            materialPath: materialPath,
            materialRawSHA256:
                "95896dcaa058cf8d80b6e0bc1f531a2e533c2da886023a5c22d336224e16e51d",
            passIndex: 0,
            shaderPath: shaderIdentity,
            texturePaths: [],
            textureSlots: [],
            userTextureInputs: [],
            combos: [:],
            constantShaderValues: [:],
            blending: "normal",
            depthTest: "disabled",
            depthWrite: "disabled",
            cullMode: "nocull"
        )
        let definitionPass = SceneEffectDefinition.Pass(
            passIndex: 0,
            materialPath: materialPath,
            target: nil,
            bindings: [],
            compose: nil,
            command: nil,
            source: nil,
            conditions: nil,
            extraFields: [:]
        )
        let definition = SceneEffectDefinition(
            relativePath: definitionPath,
            version: 2,
            replacementKey: "foliagesway",
            name: "ui_editor_effect_foliage_sway_title",
            description: "ui_editor_effect_foliage_sway_description",
            group: "animate",
            performance: nil,
            previewPath: "preview/project.json",
            editable: nil,
            passes: [definitionPass],
            framebuffers: [],
            dependencies: [
                materialPath,
                "shaders/effects/foliagesway.frag",
                "shaders/effects/foliagesway.vert",
            ],
            functions: nil,
            gizmos: nil,
            extraFields: [:],
            unknownFieldPaths: []
        )
        return .init(
            layers: [
                .init(
                    id: layerID,
                    contentKind: "image",
                    effects: [effect],
                    utilityLayer: nil
                )
            ],
            materialPasses: [material],
            effectDefinitions: [definition]
        )
    }

    static func graph() -> Graph {
        let key = Graph.EffectKey(
            layerID: layerID,
            effectIndex: 0,
            descriptorID: descriptorID
        )
        let input = Graph.TextureIdentity(
            kind: .layerSource,
            layerID: layerID,
            effect: nil,
            name: nil
        )
        let output = Graph.TextureIdentity(
            kind: .effectOutput,
            layerID: layerID,
            effect: key,
            name: nil
        )
        let node = Graph.Node(
            nodeIndex: 0,
            effect: key,
            definitionPassIndex: 0,
            materialOrdinal: 0,
            instancePassIndex: 0,
            kind: .material,
            materialPath: materialPath,
            materialPassID: materialPassID,
            target: output,
            bindings: [],
            commandSource: nil,
            commandTarget: nil,
            compose: nil,
            conditions: nil
        )
        let effect = Graph.Effect(
            key: key,
            definitionPath: definitionPath,
            input: input,
            output: output,
            nodeIndices: [0]
        )
        return .init(
            layerID: layerID,
            effects: [effect],
            renderTargets: [],
            nodes: [node],
            finalOutput: output,
            blockers: []
        )
    }

    static func planned(
        _ options: Options,
        contracts: [SceneShaderContract]
    ) -> SceneFoliageSwayExecutionPlan? {
        SceneAuthoredFoliageSwayPlanner.plan(
            graph: graph(),
            descriptor: descriptor(options),
            shaderContracts: contracts
        )
    }

    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            throw NSError(
                domain: "FoliageSwayHarness",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "missing stock effect root"]
            )
        }
        let root = URL(
            fileURLWithPath: CommandLine.arguments[1],
            isDirectory: true
        )
        let contracts = SceneShaderContractLoader().load(
            shaderReferences: [shaderIdentity],
            rootURL: root
        )

        let noMask = Options()
        let masked = Options(
            slots: [nil, maskPath, nil],
            paths: [maskPath]
        )
        let missingMaskForCombo = Options(combos: ["MASK": 1])
        let unexpectedDisabledMaskCombo = Options(combos: ["MASK": 0])
        let nonDefaultMode = Options(combos: ["MODE": 1])

        let paddedNoMaskSlots = Options(slots: [nil, nil, nil])
        let truncatedMaskSlots = Options(
            slots: [nil, maskPath],
            paths: [maskPath]
        )
        let stockExplicitNoise = Options(
            slots: [nil, maskPath, noisePath],
            paths: [maskPath, noisePath]
        )

        let pathWithoutSlot = Options(paths: [maskPath])
        let slotWithoutPath = Options(slots: [nil, maskPath, nil])
        let mismatchedMaskPath = Options(
            slots: [nil, maskPath, nil],
            paths: [otherMaskPath]
        )

        let legacySparseConstants = Options(
            constants: ["strength": value(0.4)]
        )
        let explicitNoiseV1WithoutMask = Options(
            slots: [nil, nil, noisePath],
            paths: [noisePath],
            constants: ["strength": value(0.4)]
        )

        let result: [String: Bool] = [
            "stockProfileResolved":
                SceneFoliageSwayShaderProfile.resolve(contracts) == .stock,
            "stockNoMaskAccepted": planned(noMask, contracts: contracts) != nil,
            "stockMaskedAccepted": planned(masked, contracts: contracts) != nil,
            "missingMaskForComboRejected":
                planned(missingMaskForCombo, contracts: contracts) == nil,
            "unexpectedDisabledMaskComboRejected":
                planned(unexpectedDisabledMaskCombo, contracts: contracts) == nil,
            "nonDefaultModeRejected":
                planned(nonDefaultMode, contracts: contracts) == nil,
            "paddedNoMaskSlotsRejected":
                planned(paddedNoMaskSlots, contracts: contracts) == nil,
            "truncatedMaskSlotsRejected":
                planned(truncatedMaskSlots, contracts: contracts) == nil,
            "stockExplicitNoiseRejected":
                planned(stockExplicitNoise, contracts: contracts) == nil,
            "pathWithoutSlotRejected":
                planned(pathWithoutSlot, contracts: contracts) == nil,
            "slotWithoutPathRejected":
                planned(slotWithoutPath, contracts: contracts) == nil,
            "mismatchedMaskPathRejected":
                planned(mismatchedMaskPath, contracts: contracts) == nil,
            "legacySparseConstantsRejected":
                planned(legacySparseConstants, contracts: contracts) == nil,
            "explicitNoiseV1WithoutMaskRejected":
                planned(explicitNoiseV1WithoutMask, contracts: contracts) == nil,
        ]
        let data = try JSONSerialization.data(
            withJSONObject: result,
            options: [.sortedKeys]
        )
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class SceneFoliageSwayProfileTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        swiftc = shutil.which("swiftc")
        if swiftc is None:
            raise unittest.SkipTest("swiftc is unavailable")

        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-foliage-sway-profile-"
        )
        root = Path(cls.temporary_directory.name)
        harness = root / "Harness.swift"
        executable = root / "foliage-sway-profile"
        harness.write_text(HARNESS, encoding="utf-8")

        environment = os.environ.copy()
        environment["CLANG_MODULE_CACHE_PATH"] = str(root / "clang-module-cache")
        environment["SWIFT_MODULECACHE_PATH"] = str(root / "swift-module-cache")
        compilation = subprocess.run(
            [
                swiftc,
                "-parse-as-library",
                *(str(path) for path in SWIFT_SOURCES),
                str(harness),
                "-o",
                str(executable),
            ],
            check=False,
            capture_output=True,
            text=True,
            env=environment,
        )
        if compilation.returncode != 0:
            raise AssertionError(compilation.stderr)

        completed = subprocess.run(
            [str(executable), str(STOCK_EFFECT_ROOT)],
            check=False,
            capture_output=True,
            text=True,
            env=environment,
        )
        if completed.returncode != 0:
            raise AssertionError(
                f"stdout={completed.stdout}\nstderr={completed.stderr}"
            )
        cls.result = json.loads(completed.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_stock_profile_accepts_absent_and_authored_masks(self) -> None:
        self.assertTrue(self.result["stockProfileResolved"], self.result)
        self.assertTrue(self.result["stockNoMaskAccepted"], self.result)
        self.assertTrue(self.result["stockMaskedAccepted"], self.result)

    def test_mask_and_mode_combos_remain_fail_closed(self) -> None:
        for key in (
            "missingMaskForComboRejected",
            "unexpectedDisabledMaskComboRejected",
            "nonDefaultModeRejected",
        ):
            self.assertTrue(self.result[key], self.result)

    def test_noncanonical_slots_and_paths_remain_fail_closed(self) -> None:
        for key in (
            "paddedNoMaskSlotsRejected",
            "truncatedMaskSlotsRejected",
            "stockExplicitNoiseRejected",
            "pathWithoutSlotRejected",
            "slotWithoutPathRejected",
            "mismatchedMaskPathRejected",
        ):
            self.assertTrue(self.result[key], self.result)

    def test_legacy_instance_shapes_do_not_expand_the_stock_profile(self) -> None:
        self.assertTrue(self.result["legacySparseConstantsRejected"], self.result)
        self.assertTrue(
            self.result["explicitNoiseV1WithoutMaskRejected"],
            self.result,
        )


if __name__ == "__main__":
    unittest.main()
