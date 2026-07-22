#!/usr/bin/env python3

from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
WEB_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Modules/SteamWorkshop/Web/Core"
SWIFT_SOURCES = [
    WEB_ROOT / "SteamWorkshopWebPropertyModels.swift",
    WEB_ROOT / "SteamWorkshopService+WebDisplayConditionParsing.swift",
    WEB_ROOT / "SteamWorkshopService+WebDisplayConditionSupport.swift",
]

HARNESS_SOURCE = r'''
import Foundation

final class SteamWorkshopService {}

@main
enum Harness {
    static func main() throws {
        let definitions = [
            SteamWorkshopWebPropertyDefinition(
                key: "mode",
                title: "Mode",
                kind: .combo,
                runtimeType: "combo",
                order: 0,
                minimumValue: nil,
                maximumValue: nil,
                allowsFractionalValues: false,
                fractionalPrecision: nil,
                displayCondition: nil,
                directoryMode: nil,
                fileType: nil,
                defaultValue: .string("1"),
                options: [
                    .init(label: "Automatic", value: .string("1"), displayCondition: nil),
                    .init(label: "Custom", value: .string("2"), displayCondition: nil),
                ]
            )
        ]
        let values: [String: SteamWorkshopWebPropertyValue] = [
            "mode": .string("1"),
            "enabled": .bool(true),
            "amount": .number(10),
        ]
        let conditions = [
            "singleDigitFalse": "mode.value ==2",
            "singleDigitTrue": "mode.value ==1",
            "multiDigitTrue": "amount.value ==10",
            "negativeTrue": "amount.value > -0.5",
            "logicalTrue": "enabled.value && mode.value !=2",
            "comboTextTrue": "mode.text == 'Automatic'",
        ]
        let result = conditions.mapValues {
            SteamWorkshopService.evaluateWebDisplayCondition(
                $0,
                values: values,
                definitions: definitions
            )
        }
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class WebDisplayConditionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        swiftc = shutil.which("swiftc")
        if swiftc is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(prefix="mwx-web-condition-")
        directory = Path(cls.temporary_directory.name)
        harness = directory / "Harness.swift"
        harness.write_text(HARNESS_SOURCE, encoding="utf-8")
        cls.binary = directory / "web-condition"
        subprocess.run(
            [swiftc, *(str(path) for path in SWIFT_SOURCES), str(harness), "-o", str(cls.binary)],
            check=True,
            capture_output=True,
            text=True,
        )

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_numeric_boolean_and_combo_conditions(self) -> None:
        completed = subprocess.run(
            [str(self.binary)],
            check=True,
            capture_output=True,
            text=True,
        )
        result = json.loads(completed.stdout)
        self.assertFalse(result["singleDigitFalse"])
        self.assertTrue(result["singleDigitTrue"])
        self.assertTrue(result["multiDigitTrue"])
        self.assertTrue(result["negativeTrue"])
        self.assertTrue(result["logicalTrue"])
        self.assertTrue(result["comboTextTrue"])


if __name__ == "__main__":
    unittest.main()
