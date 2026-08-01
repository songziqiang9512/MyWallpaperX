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
    SOURCE_ROOT / "Properties/SceneDynamicSnapshot.swift",
    SOURCE_ROOT / "Properties/SceneTimeOfDayEffectScriptProgram.swift",
    SOURCE_ROOT / "Properties/SceneTimeOfDayEffectScriptCompiler.swift",
    SOURCE_ROOT / "Properties/SceneTimeOfDayEffectScriptRuntime.swift",
]

HARNESS = r'''
import Foundation

struct SceneDocument {
    struct ShaderValue {
        let rawValue: String
        let valueKind: String
        let userBinding: String?
        let components: [Double]?
        let timeline: Int?
        let timelineDiagnostics: [String]
        let scriptSource: String?
        let bindingKeys: [String]
    }
}

@main
enum Harness {
    static let target = SceneDynamicTarget.effectConstant(
        layerID: 42, effectIndex: 1, passIndex: 0, name: "multiply"
    )

    static func main() throws {
        let cyclic = binding(source: cyclicSource)
        let interval = binding(source: intervalSource)
        let invalidCall = binding(source: cyclicSource.replacingOccurrences(
            of: "Math.max", with: "Math.min"
        ))
        let extraFunction = binding(source: cyclicSource + "\nfunction hidden() { return 1; }")
        let wrongWrapper = binding(source: cyclicSource, keys: ["script", "value"])
        let userBound = binding(source: cyclicSource, user: "mode")
        let malformed = binding(source: "export function update(value) { return 1; }")

        let utc = TimeZone(secondsFromGMT: 0)!
        let cyclicProgram = SceneTimeOfDayEffectScriptProgram(
            bindings: [cyclic].compactMap { $0 }
        )
        let intervalProgram = SceneTimeOfDayEffectScriptProgram(
            bindings: [interval].compactMap { $0 }
        )
        let cyclicValues = [6, 7, 12, 18, 20].map {
            scalar(SceneTimeOfDayEffectScriptRuntime.values(
                program: cyclicProgram, wallDate: date(hour: $0), timeZone: utc
            ))
        }
        let intervalValues = [6, 8, 12, 18, 20].map {
            scalar(SceneTimeOfDayEffectScriptRuntime.values(
                program: intervalProgram, wallDate: date(hour: $0), timeZone: utc
            ))
        }
        let result: [String: Any] = [
            "cyclicCompiled": cyclic != nil,
            "intervalCompiled": interval != nil,
            "invalidCallRejected": invalidCall == nil,
            "extraFunctionRejected": extraFunction == nil,
            "wrongWrapperRejected": wrongWrapper == nil,
            "userBindingRejected": userBound == nil,
            "malformedRejected": malformed == nil,
            "cyclicValues": cyclicValues,
            "intervalValues": intervalValues,
            "targetPreserved": cyclic?.definition.target == target,
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }

    static func binding(
        source: String,
        keys: [String] = ["script", "user", "value"],
        user: String? = nil
    ) -> SceneTimeOfDayEffectScriptBinding? {
        SceneTimeOfDayEffectScriptCompiler.compile(
            value: .init(
                rawValue: "1", valueKind: "binding", userBinding: user,
                components: [1], timeline: nil, timelineDiagnostics: [],
                scriptSource: source, bindingKeys: keys
            ),
            target: target
        )
    }

    static func scalar(_ values: [SceneDynamicTarget: SceneDynamicValue]) -> Double {
        guard case let .scalar(value)? = values[target] else { return -1 }
        return value
    }

    static func date(hour: Int) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = 2026
        components.month = 8
        components.day = 1
        components.hour = hour
        return components.date!
    }

    static let cyclicSource = """
    'use strict';
    import * as WEMath from 'WEMath';
    const MORNING = 7;
    const EVENING = 18;
    export function update(value) {
        return Math.max(
            WEMath.smoothStep(MORNING / 24, (MORNING - 0.004) / 24, engine.timeOfDay),
            WEMath.smoothStep((EVENING - 0.004) / 24, EVENING / 24, engine.timeOfDay)
        );
    }
    """

    static let intervalSource = """
    'use strict';
    import * as WEMath from 'WEMath';
    const OPEN = 7;
    const CLOSE = 18;
    const FADE = 0.004;
    export function update(value) {
        return WEMath.smoothStep((OPEN - FADE) / 24, OPEN / 24, engine.timeOfDay)
            * WEMath.smoothStep(CLOSE / 24, (CLOSE - FADE) / 24, engine.timeOfDay);
    }
    """
}
'''


class SceneTimeOfDayEffectScriptTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(prefix="mwx-time-of-day-effect-")
        root = Path(cls.temporary_directory.name)
        harness = root / "Harness.swift"
        binary = root / "time-of-day-effect"
        harness.write_text(HARNESS, encoding="utf-8")
        compilation = subprocess.run(
            [
                "xcrun", "--sdk", "macosx", "swiftc", "-parse-as-library",
                *(str(path) for path in SWIFT_SOURCES), str(harness),
                "-module-cache-path", str(root / "module-cache"), "-o", str(binary),
            ],
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)
        completed = subprocess.run([str(binary)], check=True, capture_output=True, text=True)
        cls.result = json.loads(completed.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_documented_time_of_day_expression_shapes_are_bounded(self) -> None:
        self.assertTrue(self.result["cyclicCompiled"])
        self.assertTrue(self.result["intervalCompiled"])
        self.assertEqual(self.result["cyclicValues"], [1, 0, 0, 1, 1])
        self.assertEqual(self.result["intervalValues"], [0, 1, 1, 0, 0])
        self.assertTrue(self.result["targetPreserved"])

    def test_unknown_syntax_and_wrapper_mutations_fail_closed(self) -> None:
        for key in [
            "invalidCallRejected", "extraFunctionRejected", "wrongWrapperRejected",
            "userBindingRejected", "malformedRejected",
        ]:
            self.assertTrue(self.result[key], key)


if __name__ == "__main__":
    unittest.main()
