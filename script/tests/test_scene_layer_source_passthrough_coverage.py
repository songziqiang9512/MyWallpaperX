#!/usr/bin/env python3

"""Executable coverage contract for degraded image-layer source passthrough."""

from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SOURCE = (
    REPOSITORY_ROOT
    / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/SceneImageLayerDrawRequest.swift"
)

HARNESS = r'''
import Foundation

enum SceneBlendModeShaderSource {
    static let maximumMode = 19
}

struct SceneRenderDescriptor {
    struct EffectDescriptor {
        struct PassDescriptor {
            let passIndex: Int
            let texturePaths: [String]
            let textureSlots: [String?]
            let userTextureInputs: [String?]
            let combos: [String: Int]
        }

        let file: String
        let visible: Bool?
        let passes: [PassDescriptor]
    }
}

func effect(
    path: String = "effects/waterwaves/effect.json",
    slots: [String?] = [],
    paths: [String] = [],
    combos: [String: Int] = [:],
    passIndex: Int = 0,
    passCount: Int = 1
) -> SceneRenderDescriptor.EffectDescriptor {
    let pass = SceneRenderDescriptor.EffectDescriptor.PassDescriptor(
        passIndex: passIndex,
        texturePaths: paths,
        textureSlots: slots,
        userTextureInputs: [],
        combos: combos
    )
    return .init(
        file: path,
        visible: true,
        passes: Array(repeating: pass, count: passCount)
    )
}

let shake = SceneRenderDescriptor.EffectDescriptor(
    file: "effects/shake/effect.json",
    visible: true,
    passes: [
        .init(
            passIndex: 0,
            texturePaths: ["masks/a", "masks/b"],
            textureSlots: [nil, "masks/a", "masks/b"],
            userTextureInputs: [],
            combos: [:]
        )
    ]
)
let masks = SceneImageLayerMasks.empty
let results: [String: Bool] = [
    "implicitSource": masks.blocksLayerSourcePassthrough(
        forVisibleEffects: [effect()]
    ),
    "implicitSourceThenShake": masks.blocksLayerSourcePassthrough(
        forVisibleEffects: [effect(), shake]
    ),
    "explicitSource": masks.blocksLayerSourcePassthrough(
        forVisibleEffects: [effect(slots: [nil])]
    ),
    "explicitMask": masks.blocksLayerSourcePassthrough(
        forVisibleEffects: [
            effect(slots: [nil, "masks/wave"], paths: ["masks/wave"])
        ]
    ),
    "replacedSource": masks.blocksLayerSourcePassthrough(
        forVisibleEffects: [
            effect(slots: ["textures/replacement"], paths: ["textures/replacement"])
        ]
    ),
    "emptyOptionalMask": masks.blocksLayerSourcePassthrough(
        forVisibleEffects: [effect(slots: [nil, nil])]
    ),
    "unknownCombo": masks.blocksLayerSourcePassthrough(
        forVisibleEffects: [effect(combos: ["UNKNOWN": 0])]
    ),
    "nonzeroCombo": masks.blocksLayerSourcePassthrough(
        forVisibleEffects: [effect(combos: ["DUALWAVES": 1])]
    ),
    "relocatedDefinition": masks.blocksLayerSourcePassthrough(
        forVisibleEffects: [
            effect(path: "effects/workshop/waterwaves/effect.json")
        ]
    ),
    "multiplePasses": masks.blocksLayerSourcePassthrough(
        forVisibleEffects: [effect(passCount: 2)]
    ),
]
let data = try! JSONSerialization.data(withJSONObject: results, options: [.sortedKeys])
print(String(data: data, encoding: .utf8)!)
'''


class SceneLayerSourcePassthroughCoverageTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        swiftc = shutil.which("swiftc")
        if swiftc is None:
            raise unittest.SkipTest("swiftc is required")
        cls._temporary = tempfile.TemporaryDirectory(
            prefix="mwx-scene-source-coverage-"
        )
        directory = Path(cls._temporary.name)
        source_text = SOURCE.read_text()
        boundary = "struct SceneImageLayerUniformValues"
        coverage_source, separator, _ = source_text.partition(boundary)
        if not separator:
            raise AssertionError("coverage source boundary is missing")
        extracted = directory / "SceneImageLayerMasks.swift"
        extracted.write_text(coverage_source.replace("import Metal\n", ""))
        harness = directory / "main.swift"
        harness.write_text(HARNESS)
        cls.binary = directory / "scene-layer-source-coverage"
        compilation = subprocess.run(
            [swiftc, str(extracted), str(harness), "-o", str(cls.binary)],
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            raise AssertionError(compilation.stderr)

    @classmethod
    def tearDownClass(cls) -> None:
        cls._temporary.cleanup()

    def test_implicit_source_is_safe_but_unproven_overrides_stay_blocked(self) -> None:
        completed = subprocess.run(
            [str(self.binary)], check=True, capture_output=True, text=True
        )
        result = json.loads(completed.stdout)
        self.assertFalse(result["implicitSource"])
        self.assertFalse(result["implicitSourceThenShake"])
        self.assertFalse(result["explicitSource"])
        self.assertFalse(result["explicitMask"])
        self.assertTrue(result["replacedSource"])
        self.assertTrue(result["emptyOptionalMask"])
        self.assertTrue(result["unknownCombo"])
        self.assertTrue(result["nonzeroCombo"])
        self.assertTrue(result["relocatedDefinition"])
        self.assertTrue(result["multiplePasses"])


if __name__ == "__main__":
    unittest.main()
