#!/usr/bin/env python3

from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SWIFT_SOURCES = [
    Path(__file__).with_name("fixtures")
    / "SceneDependencyRenderPlanTestSupport.swift",
    SCENE_ROOT / "Resources/SceneNamedTextureReference.swift",
    SCENE_ROOT
    / "RenderGraph/LayerDependencies/SceneImageLayerBlendDependencyContract.swift",
    SCENE_ROOT
    / "RenderGraph/LayerDependencies/SceneNamedTextureDependencyReferenceAnalysis.swift",
    SCENE_ROOT / "RenderGraph/LayerDependencies/SceneDependencyGraphAnalysis.swift",
    SCENE_ROOT
    / "RenderGraph/LayerDependencies/SceneDependencyRenderPlan+ImageProgramReference.swift",
    SCENE_ROOT
    / "RenderGraph/LayerDependencies/SceneDependencyRenderPlan+StaticModel.swift",
    SCENE_ROOT / "RenderGraph/LayerDependencies/SceneDependencyRenderPlan.swift",
]


HARNESS_SOURCE = r'''
import Foundation

private let providerLayerID = 260
private let consumerLayerID = 261
private let consumerEffectID = "xray-provider-consumer"

private func provider() -> SceneRenderDescriptor.Layer {
    let pass = SceneRenderDescriptor.EffectDescriptor.PassDescriptor(
        passIndex: 0,
        texturePaths: ["textures/provider-source.jpg"],
        textureSlots: ["textures/provider-source.jpg"],
        userTextureInputs: [],
        combos: [:],
        constantShaderValues: [:]
    )
    return .init(
        id: providerLayerID,
        contentKind: "image",
        utilityLayer: nil,
        dependencyLayerIDs: [],
        childLayerIDs: [],
        visible: true,
        effects: [.init(
            id: "provider-effect",
            file: "effects/tint/effect.json",
            visible: true,
            passes: [pass]
        )]
    )
}

private func consumer(
    passIndex: Int = 0,
    slotIndex: Int = 1,
    variantSuffix: String = "a"
) -> SceneRenderDescriptor.Layer {
    let path = "_rt_imageLayerComposite_\(providerLayerID)_\(variantSuffix)"
    var slots = [String?](repeating: nil, count: max(3, slotIndex + 1))
    slots[slotIndex] = path
    let pass = SceneRenderDescriptor.EffectDescriptor.PassDescriptor(
        passIndex: passIndex,
        texturePaths: slots.compactMap { $0 },
        textureSlots: slots,
        userTextureInputs: [],
        combos: ["BLENDMODE": 0],
        constantShaderValues: [
            "size": .init(components: [0.5]),
            "multiply": .init(components: [1]),
        ]
    )
    return .init(
        id: consumerLayerID,
        contentKind: "image",
        utilityLayer: nil,
        dependencyLayerIDs: [providerLayerID],
        childLayerIDs: [],
        visible: true,
        effects: [.init(
            id: consumerEffectID,
            file: "effects/xray/effect.json",
            visible: true,
            passes: [pass]
        )]
    )
}

private func plan(
    passIndex: Int = 0,
    slotIndex: Int = 1,
    variantSuffix: String = "a"
) -> SceneDependencyRenderPlan {
    let layers = [
        provider(),
        consumer(
            passIndex: passIndex,
            slotIndex: slotIndex,
            variantSuffix: variantSuffix
        ),
    ]
    return SceneDependencyRenderPlan(
        descriptor: .init(
            layers: layers,
            renderOrderLayerIDs: layers.map(\.id)
        ),
        visibleLayerIDs: Set(layers.map(\.id)),
        verifiedXRayStageKeys: [.init(
            layerID: consumerLayerID,
            effectIndex: 0,
            descriptorID: consumerEffectID
        )]
    )
}

@main
private enum VisibleGraphOutputPlanHarness {
    static func main() throws {
        let positive = plan()
        let binding = positive.bindingsByConsumerLayerID[consumerLayerID]
        let wrongPass = plan(passIndex: 1)
        let wrongSlot = plan(slotIndex: 2)
        let secondary = plan(variantSuffix: "b")
        let result: [String: Any] = [
            "positiveKind": binding?.kind == .visibleImageGraphOutput,
            "positivePass": binding?.slot.passIndex ?? -1,
            "positiveSlot": binding?.slot.slotIndex ?? -1,
            "positivePrimary": positive.references.count == 1
                && positive.references.first?.variant == .primary,
            "positiveProvider": binding?.providerLayerID ?? -1,
            "positiveGraphProviders": positive
                .requiredGraphOutputProviderLayerIDs.sorted(),
            "providerHasExecutablePass": provider().effects.first?.passes.count == 1,
            "wrongPassRejected":
                wrongPass.bindingsByConsumerLayerID[consumerLayerID] == nil,
            "wrongSlotRejected":
                wrongSlot.bindingsByConsumerLayerID[consumerLayerID] == nil,
            "secondaryRejected":
                secondary.bindingsByConsumerLayerID[consumerLayerID] == nil,
        ]
        let data = try JSONSerialization.data(
            withJSONObject: result,
            options: [.sortedKeys]
        )
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


@unittest.skipUnless(shutil.which("swiftc"), "swiftc is required")
class SceneVisibleGraphOutputRenderPlanTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-visible-graph-output-plan-"
        )
        root = Path(cls.temporary_directory.name)
        harness = root / "Harness.swift"
        harness.write_text(HARNESS_SOURCE, encoding="utf-8")
        cls.binary = root / "visible-graph-output-plan"
        compilation = subprocess.run(
            [
                "xcrun",
                "--sdk",
                "macosx",
                "swiftc",
                *(str(path) for path in SWIFT_SOURCES),
                str(harness),
                "-o",
                str(cls.binary),
            ],
            cwd=REPOSITORY_ROOT,
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def run_harness(self, *, route_disabled: bool = False) -> dict:
        environment = os.environ.copy()
        if route_disabled:
            environment["MWX_SCENE_NAMED_PROVIDER_ROUTE"] = "disable-generic"
        else:
            environment.pop("MWX_SCENE_NAMED_PROVIDER_ROUTE", None)
        completed = subprocess.run(
            [str(self.binary)],
            cwd=REPOSITORY_ROOT,
            env=environment,
            check=True,
            capture_output=True,
            text=True,
        )
        return json.loads(completed.stdout)

    def test_pass_zero_slot_one_primary_is_the_only_typed_carrier(self) -> None:
        result = self.run_harness()
        self.assertTrue(result["positiveKind"], result)
        self.assertEqual(result["positivePass"], 0, result)
        self.assertEqual(result["positiveSlot"], 1, result)
        self.assertTrue(result["positivePrimary"], result)
        self.assertEqual(result["positiveProvider"], 260, result)
        self.assertEqual(result["positiveGraphProviders"], [260], result)
        self.assertTrue(result["providerHasExecutablePass"], result)

    def test_wrong_pass_slot_and_secondary_variant_fail_closed(self) -> None:
        result = self.run_harness()
        self.assertTrue(result["wrongPassRejected"], result)
        self.assertTrue(result["wrongSlotRejected"], result)
        self.assertTrue(result["secondaryRejected"], result)

    def test_legacy_named_provider_disable_does_not_revoke_visible_output(self) -> None:
        result = self.run_harness(route_disabled=True)
        self.assertTrue(result["positiveKind"], result)
        self.assertEqual(result["positiveGraphProviders"], [260], result)


if __name__ == "__main__":
    unittest.main()
