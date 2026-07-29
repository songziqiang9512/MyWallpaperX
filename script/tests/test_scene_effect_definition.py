#!/usr/bin/env python3

from __future__ import annotations

import hashlib
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
    SOURCE_ROOT / "Resources/SceneResourceIndex.swift",
]


BLUR_FIXTURE = {
    "version": 1,
    "replacementkey": "blur",
    "passes": [
        {
            "material": "materials/effects/downsample.json",
            "target": "_rt_Quarter1",
            "bind": [{"name": "previous", "index": 0}],
        },
        {
            "material": "materials/effects/gaussian_x.json",
            "target": "_rt_Quarter2",
            "bind": [{"name": "_rt_Quarter1", "index": 0}],
        },
        {
            "material": "materials/effects/gaussian_y.json",
            "target": "_rt_Quarter1",
            "bind": [{"name": "_rt_Quarter2", "index": 0}],
        },
        {
            "material": "materials/effects/combine.json",
            "bind": [
                {"name": "_rt_Quarter1", "index": 0},
                {"name": "previous", "index": 2},
            ],
        },
    ],
    "fbos": [
        {"name": "_rt_Quarter1", "scale": 4, "format": "rgba_backbuffer"},
        {"name": "_rt_Quarter2", "scale": 4, "format": "rgba_backbuffer"},
    ],
    "dependencies": ["materials/effects/downsample.json"],
}


MOTION_JSON5 = r'''
{
  "version": 1,
  "replacementkey": "motionblur",
  "passes": [
    {
      "material": "materials/effects/accumulation.json",
      "target": "_rt_Full2",
      "bind": [
        {"name": "previous", "index": 0},
        {"name": "_rt_Full1", "index": 1},
      ],
    },
    {"command": "copy", "source": "_rt_Full2", "target": "_rt_Full1"},
    {
      "material": "materials/effects/combine.json",
      "bind": [{"name": "_rt_Full2", "index": 0}],
    },
  ],
  "fbos": [
    {"name": "_rt_Full1", "scale": 1, "format": "rgba_backbuffer", "unique": true},
    {"name": "_rt_Full2", "scale": 1, "format": "rgba_backbuffer"},
  ],
  "dependencies": ["materials/effects/accumulation.json"],
}
'''


FLUID_JSON5 = r'''
{
  "version": 1,
  "passes": [
    {
      "material": "materials/effects/fluid.json",
      "target": "_rt_Dye",
      "bind": [
        {
          "name": "_rt_Velocity",
          "index": 4,
          "conditions": [{"RENDERING": 3}],
          "futurebind": "kept",
        },
      ],
      "conditions": [{"LIGHTING": 1}],
      "futurepass": true,
    },
    {"command": "swap", "source": "_rt_Dye", "target": "_rt_History"},
  ],
  "fbos": [
    {
      "name": "_rt_Dye",
      "fit": 256,
      "format": "rg1616f",
      "clear": "0 0 0 0",
      "unique": true,
      "conditions": [{"LIGHTING": 1}],
      "futurefbo": 3,
    },
  ],
  "functions": {"clearDye": {"action": "clear", "fbos": ["_rt_Dye"]}},
  "gizmos": [{"type": "EffectPointEmitter", "condition": {"POINTEMITTER": 1}}],
  "futurefield": {"version": 2},
}
'''


HARNESS_SOURCE = r'''
import Foundation

@main
enum Harness {
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let index = SceneResourceIndexBuilder().build(rootURL: root)
        let effectResources = index.resources.filter { $0.kind == .effectDefinition }
        let loader = SceneEffectDefinitionLoader()
        let definitions = try ["blur", "motion", "fluid"].map { name in
            try loader.load(
                from: root.appendingPathComponent("effects/\(name)/effect.json"),
                relativePath: "effects/\(name)/effect.json"
            )
        }
        let blur = definitions[0]
        let motion = definitions[1]
        let fluid = definitions[2]
        let encoded = try JSONEncoder().encode(definitions)
        let roundTrip = try JSONDecoder().decode([SceneEffectDefinition].self, from: encoded)

        let invalidRejected: Bool
        do {
            _ = try loader.load(
                from: root.appendingPathComponent("effects/broken/effect.json"),
                relativePath: "effects/broken/effect.json"
            )
            invalidRejected = false
        } catch {
            invalidRejected = true
        }

        let result: [String: Any] = [
            "effectResourceCount": effectResources.count,
            "resourceKinds": Array(Set(effectResources.map { $0.kind.rawValue })).sorted(),
            "blurMaterials": blur.passes.map { $0.materialPath ?? "" },
            "blurTargets": blur.passes.map { $0.target ?? "output" },
            "blurBindings": blur.passes.map { pass in
                pass.bindings.map { "\($0.name ?? "nil"):\($0.index ?? -1)" }
            },
            "blurScales": blur.framebuffers.map { $0.scale?.numberValue ?? -1 },
            "motionCommands": motion.passes.map { $0.command ?? "material" },
            "motionMaterialPassCount": motion.materialPassCount,
            "motionCopy": [motion.passes[1].source ?? "", motion.passes[1].target ?? ""],
            "motionUnique": motion.framebuffers.map { $0.unique?.boolValue ?? false },
            "fluidCommand": fluid.passes[1].command ?? "",
            "fluidConditionsPreserved": fluid.passes[0].conditions != nil
                && fluid.passes[0].bindings[0].conditions != nil
                && fluid.framebuffers[0].conditions != nil,
            "fluidFunctionsPreserved": fluid.functions != nil,
            "fluidGizmosPreserved": fluid.gizmos != nil,
            "fluidFit": fluid.framebuffers[0].fit?.numberValue ?? -1,
            "unknownPaths": fluid.unknownFieldPaths,
            "rawHashes": definitions.map { $0.rawSHA256 ?? "" },
            "roundTrip": roundTrip == definitions,
            "invalidRejected": invalidRejected,
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class SceneEffectDefinitionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(prefix="mwx-scene-effect-ir-")
        root = Path(cls.temporary_directory.name)
        for name in ("blur", "motion", "fluid", "broken"):
            (root / "effects" / name).mkdir(parents=True)
        (root / "effects/blur/effect.json").write_text(
            json.dumps(BLUR_FIXTURE), encoding="utf-8"
        )
        (root / "effects/motion/effect.json").write_text(MOTION_JSON5, encoding="utf-8")
        (root / "effects/fluid/effect.json").write_text(FLUID_JSON5, encoding="utf-8")
        (root / "effects/broken/effect.json").write_text("[", encoding="utf-8")
        harness = root / "Harness.swift"
        harness.write_text(HARNESS_SOURCE, encoding="utf-8")
        cls.binary = root / "scene-effect-definition"
        subprocess.run(
            [
                "xcrun", "--sdk", "macosx", "swiftc",
                *(str(path) for path in SWIFT_SOURCES),
                str(harness), "-o", str(cls.binary),
            ],
            check=True,
            capture_output=True,
            text=True,
        )
        completed = subprocess.run(
            [str(cls.binary), str(root)], check=True, capture_output=True, text=True
        )
        cls.result = json.loads(completed.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_effect_files_are_typed_resources(self) -> None:
        self.assertEqual(self.result["effectResourceCount"], 4)
        self.assertEqual(self.result["resourceKinds"], ["effectDefinition"])
        self.assertTrue(self.result["invalidRejected"])

    def test_blur_preserves_ordered_passes_targets_bindings_and_fbos(self) -> None:
        self.assertEqual(
            self.result["blurMaterials"],
            [
                "materials/effects/downsample.json",
                "materials/effects/gaussian_x.json",
                "materials/effects/gaussian_y.json",
                "materials/effects/combine.json",
            ],
        )
        self.assertEqual(
            self.result["blurTargets"],
            ["_rt_Quarter1", "_rt_Quarter2", "_rt_Quarter1", "output"],
        )
        self.assertEqual(self.result["blurBindings"][-1], ["_rt_Quarter1:0", "previous:2"])
        self.assertEqual(self.result["blurScales"], [4, 4])

    def test_json5_copy_and_unique_history_are_preserved(self) -> None:
        self.assertEqual(self.result["motionCommands"], ["material", "copy", "material"])
        self.assertEqual(self.result["motionMaterialPassCount"], 2)
        self.assertEqual(self.result["motionCopy"], ["_rt_Full2", "_rt_Full1"])
        self.assertEqual(self.result["motionUnique"], [True, False])

    def test_conditions_functions_gizmos_and_unknown_fields_are_not_dropped(self) -> None:
        self.assertEqual(self.result["fluidCommand"], "swap")
        self.assertTrue(self.result["fluidConditionsPreserved"])
        self.assertTrue(self.result["fluidFunctionsPreserved"])
        self.assertTrue(self.result["fluidGizmosPreserved"])
        self.assertEqual(self.result["fluidFit"], 256)
        self.assertEqual(
            self.result["unknownPaths"],
            [
                "fbos[0].futurefbo",
                "futurefield",
                "passes[0].bind[0].futurebind",
                "passes[0].futurepass",
            ],
        )
        self.assertTrue(self.result["roundTrip"])

    def test_raw_definition_fingerprints_are_preserved(self) -> None:
        root = Path(self.temporary_directory.name)
        expected = [
            hashlib.sha256(
                (root / "effects" / name / "effect.json").read_bytes()
            ).hexdigest()
            for name in ("blur", "motion", "fluid")
        ]
        self.assertEqual(self.result["rawHashes"], expected)


if __name__ == "__main__":
    unittest.main()
