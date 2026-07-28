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
    SOURCE_ROOT / "Rendering/SceneMetalPipeline.swift",
    SOURCE_ROOT / "RenderGraph/SceneEffectMaskSemantics.swift",
    SOURCE_ROOT / "Effects/SceneInlineEffectRuntime.swift",
    SOURCE_ROOT / "Effects/SceneEffectRuntimeSupport.swift",
]

HARNESS_SOURCE = r'''
import Foundation

struct SceneRenderDescriptor {
    struct EffectDescriptor {
        struct PassDescriptor {
            let texturePaths: [String]
            let textureSlots: [String?]
            let combos: [String: Int]
        }
        let file: String
        let visible: Bool?
        let passes: [PassDescriptor]
    }
    struct Layer { let effects: [EffectDescriptor] }
}

@main
enum Harness {
    static func main() throws {
        let maskedFoliage = effect(
            "effects/foliagesway/effect.json", slot1: "ChatGPT Image 4x upscale_depth"
        )
        let plainFoliage = effect("effects/foliagesway/effect.json")
        let maskedWater = effect("effects/waterwaves/effect.json", maskCombo: 1)
        let plainWater = effect("effects/waterwaves/effect.json")
        let hiddenTint = effect("effects/tint/effect.json", visible: false)
        let visibleTint = effect("effects/tint/effect.json")
        let chromatic = effect("effects/chromaticaberration/effect.json")
        let workshopChromatic = effect("effects/workshop/2423877731/chromatic_aberration/effect.json")
        let cursorRipple = effect("effects/cursorripple/effect.json")
        let result: [String: Any] = [
            "missingFoliageMask": raw([maskedFoliage], water: false, foliage: false),
            "loadedFoliageMask": raw([maskedFoliage], water: false, foliage: true),
            "unmaskedFoliage": raw([plainFoliage], water: false, foliage: false),
            "missingWaterMask": raw([maskedWater], water: false, foliage: false),
            "loadedWaterMask": raw([maskedWater], water: true, foliage: false),
            "missingWaterSummary": SceneInlineEffectRuntime.summary(
                for: .init(effects: [maskedWater]), hasWaterMask: false
            ) ?? "none",
            "loadedWaterSummary": SceneInlineEffectRuntime.summary(
                for: .init(effects: [maskedWater]), hasWaterMask: true
            ) ?? "none",
            "strictWaterFlags": raw(
                [maskedWater], water: true, foliage: false, handlesWaterWaves: true
            ),
            "strictWaterSummary": SceneInlineEffectRuntime.summary(
                for: .init(effects: [maskedWater]),
                hasWaterMask: true,
                handlesWaterWaves: true
            ) ?? "none",
            "orderedWaterChain": raw(
                [visibleTint, plainWater], water: false, foliage: false
            ),
            "multipleWaterDeclarations": raw(
                [plainWater, plainWater], water: false, foliage: false
            ),
            "hiddenCompanionWater": raw(
                [hiddenTint, plainWater], water: false, foliage: false
            ),
            "orderedWaterSummary": SceneInlineEffectRuntime.summary(
                for: .init(effects: [visibleTint, plainWater]), hasWaterMask: false
            ) ?? "none",
            "depthMaskPath": SceneEffectMaskSemantics.maskPath(in: maskedFoliage.passes[0]) ?? "none",
            "comboDeclaresMask": SceneEffectMaskSemantics.declaresMask(in: maskedWater),
            "utilityMaskedFoliage": SceneEffectRuntimeSupport.supportsUtilityCapture(maskedFoliage),
            "utilityPlainFoliage": SceneEffectRuntimeSupport.supportsUtilityCapture(plainFoliage),
            "utilityCursorRipple": SceneEffectRuntimeSupport.supportsUtilityCapture(cursorRipple),
            "cursorRippleInlineFlags": raw(
                [cursorRipple], water: false, foliage: true
            ),
            "chromatic": raw([chromatic], water: false, foliage: false),
            "workshopChromatic": raw([workshopChromatic], water: false, foliage: false),
            "utilityWorkshopChromatic": SceneEffectRuntimeSupport.supportsUtilityCapture(workshopChromatic),
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }

    static func effect(
        _ file: String,
        slot1: String? = nil,
        maskCombo: Int? = nil,
        visible: Bool = true
    ) -> SceneRenderDescriptor.EffectDescriptor {
        let textureSlots: [String?] = slot1.map { [nil, $0, nil] } ?? []
        let combos: [String: Int] = maskCombo.map { ["mask": $0] } ?? [:]
        return .init(
            file: file,
            visible: visible,
            passes: [.init(
                texturePaths: textureSlots.compactMap { $0 },
                textureSlots: textureSlots,
                combos: combos
            )]
        )
    }

    static func raw(
        _ effects: [SceneRenderDescriptor.EffectDescriptor],
        water: Bool,
        foliage: Bool,
        handlesWaterWaves: Bool = false
    ) -> UInt32 {
        SceneInlineEffectRuntime.flags(
            for: .init(effects: effects),
            usesNormalWaterRipple: false,
            hasWaterMask: water,
            hasFoliageMask: foliage,
            handlesWaterWaves: handlesWaterWaves
        ).rawValue
    }
}
'''


class SceneEffectMaskGatingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(prefix="mwx-scene-mask-gate-")
        directory = Path(cls.temporary_directory.name)
        harness = directory / "Harness.swift"
        harness.write_text(HARNESS_SOURCE, encoding="utf-8")
        cls.binary = directory / "scene-effect-mask-gate"
        compilation = subprocess.run(
            [
                "xcrun", "--sdk", "macosx", "swiftc",
                *(str(path) for path in SWIFT_SOURCES),
                str(harness), "-framework", "Metal", "-o", str(cls.binary),
            ],
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)
        completed = subprocess.run(
            [str(cls.binary)], check=True, capture_output=True, text=True
        )
        cls.result = json.loads(completed.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_authored_masks_are_required_before_masked_effects_run(self) -> None:
        self.assertEqual(self.result["missingFoliageMask"], 0)
        self.assertNotEqual(self.result["loadedFoliageMask"], 0)
        self.assertEqual(self.result["missingWaterMask"], 0)
        self.assertNotEqual(self.result["loadedWaterMask"], 0)
        self.assertEqual(self.result["missingWaterSummary"], "none")
        self.assertIn("waterwaves-legacy", self.result["loadedWaterSummary"])
        self.assertEqual(self.result["strictWaterFlags"], 0)
        self.assertEqual(self.result["strictWaterSummary"], "none")
        self.assertEqual(self.result["depthMaskPath"], "ChatGPT Image 4x upscale_depth")
        self.assertTrue(self.result["comboDeclaresMask"])

    def test_unmasked_and_unrelated_effects_remain_available(self) -> None:
        self.assertNotEqual(self.result["unmaskedFoliage"], 0)
        self.assertNotEqual(self.result["chromatic"], 0)
        self.assertNotEqual(self.result["workshopChromatic"], 0)
        self.assertTrue(self.result["utilityWorkshopChromatic"])
        self.assertFalse(self.result["utilityMaskedFoliage"])
        self.assertTrue(self.result["utilityPlainFoliage"])
        self.assertFalse(self.result["utilityCursorRipple"])
        self.assertEqual(self.result["cursorRippleInlineFlags"], 0)

    def test_water_waves_inline_fallback_requires_a_single_visible_effect(self) -> None:
        self.assertEqual(self.result["orderedWaterChain"], 0)
        self.assertEqual(self.result["multipleWaterDeclarations"], 0)
        self.assertNotEqual(self.result["hiddenCompanionWater"], 0)
        self.assertEqual(self.result["orderedWaterSummary"], "none")


if __name__ == "__main__":
    unittest.main()
