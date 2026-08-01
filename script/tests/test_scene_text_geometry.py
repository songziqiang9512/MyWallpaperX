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
    SOURCE_ROOT / "Text/SceneTextDescriptor.swift",
    SOURCE_ROOT / "Text/SceneTextGeometry.swift",
]


HARNESS_SOURCE = r'''
import Foundation

enum SceneDocumentLoader {
    static func floatValue(_ raw: Any?) -> Float? {
        let value: Any?
        if let wrapped = raw as? [String: Any] {
            value = wrapped["value"]
        } else {
            value = raw
        }
        if let number = value as? NSNumber { return number.floatValue }
        if let string = value as? String { return Float(string) }
        return nil
    }

    static func floatVector(_ raw: Any?) -> [Float]? {
        let value: Any?
        if let wrapped = raw as? [String: Any] {
            value = wrapped["value"]
        } else {
            value = raw
        }
        if let values = value as? [NSNumber] {
            return values.map(\.floatValue)
        }
        guard let string = value as? String else { return nil }
        let separators = CharacterSet.whitespacesAndNewlines
            .union(CharacterSet(charactersIn: ","))
        let values = string.components(separatedBy: separators)
            .filter { !$0.isEmpty }
            .compactMap(Float.init)
        return values.isEmpty ? nil : values
    }
}

@main
enum Harness {
    static func main() throws {
        let vectorPadding = SceneTextDescriptor.parse([
            "text": "Clock",
            "padding": "32.00000 32.00000",
        ])
        let wrappedPadding = SceneTextDescriptor.parse([
            "text": "Clock",
            "padding": ["value": "82.00000 82.00000"],
        ])
        let wrappedPointSize = SceneTextDescriptor.parse([
            "text": "Clock",
            "pointsize": ["value": 42],
        ])
        let defaultAnchor = SceneTextDescriptor.parse(["text": "Clock"])
        let authoredAnchor = SceneTextDescriptor.parse([
            "text": "00000",
            "anchor": "topright",
        ])
        let wrappedAnchor = SceneTextDescriptor.parse([
            "text": "00000",
            "anchor": ["value": "bottomleft"],
        ])
        let result: [String: Any] = [
            "point32": SceneTextGeometry.pointSizeInPixels(32),
            "point64": SceneTextGeometry.pointSizeInPixels(64),
            "point300": SceneTextGeometry.pointSizeInPixels(300),
            "pointZero": SceneTextGeometry.pointSizeInPixels(0),
            "rasterLayout": rasterLayout(),
            "vectorPadding": vectorPadding.padding,
            "wrappedPadding": wrappedPadding.padding,
            "wrappedPointSize": SceneTextGeometry.pointSizeInPixels(
                wrappedPointSize.pointSize
            ),
            "defaultAnchor": defaultAnchor.screenAnchor,
            "authoredAnchor": authoredAnchor.screenAnchor,
            "wrappedAnchor": wrappedAnchor.screenAnchor,
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }

    static func rasterLayout() -> [String: Any] {
        let layout = SceneTextGeometry.rasterLayout(
            renderSize: [100, 50], padding: 10, maxDimension: 2_048
        )!
        return [
            "width": layout.width,
            "height": layout.height,
            "padding": layout.padding,
            "contentWidth": layout.contentWidth,
            "contentHeight": layout.contentHeight,
        ]
    }
}
'''


class SceneTextGeometryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        missing_sources = [path for path in SWIFT_SOURCES if not path.exists()]
        if missing_sources:
            raise RuntimeError(
                "Scene text production contract is missing: "
                + ", ".join(path.name for path in missing_sources)
            )

        cls.temporary_directory = tempfile.TemporaryDirectory(prefix="mwx-scene-text-")
        directory = Path(cls.temporary_directory.name)
        harness = directory / "Harness.swift"
        harness.write_text(HARNESS_SOURCE, encoding="utf-8")
        binary = directory / "scene-text-geometry"
        compilation = subprocess.run(
            [
                "xcrun", "--sdk", "macosx", "swiftc",
                *(str(path) for path in SWIFT_SOURCES),
                str(harness),
                "-o", str(binary),
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
        if hasattr(cls, "temporary_directory"):
            cls.temporary_directory.cleanup()

    def test_authored_point_size_uses_we_pixel_scale_and_cap(self) -> None:
        self.assertAlmostEqual(self.result["point32"], 400 / 3, places=4)
        self.assertAlmostEqual(self.result["point64"], 800 / 3, places=4)
        self.assertAlmostEqual(
            self.result["point64"] / self.result["point32"], 2, places=6
        )
        self.assertEqual(self.result["point300"], 1024)
        self.assertEqual(self.result["pointZero"], 1)

    def test_padding_vector_and_wrapped_value_use_first_component(self) -> None:
        self.assertEqual(self.result["vectorPadding"], 32)
        self.assertEqual(self.result["wrappedPadding"], 82)

    def test_wrapped_property_point_size_keeps_we_pixel_scale(self) -> None:
        self.assertEqual(self.result["wrappedPointSize"], 175)

    def test_authored_size_is_the_padded_outer_raster_frame(self) -> None:
        self.assertEqual(self.result["rasterLayout"], {
            "width": 100,
            "height": 50,
            "padding": 10,
            "contentWidth": 80,
            "contentHeight": 30,
        })

    def test_screen_anchor_defaults_to_none_and_unwraps_property_values(self) -> None:
        self.assertEqual(self.result["defaultAnchor"], "none")
        self.assertEqual(self.result["authoredAnchor"], "topright")
        self.assertEqual(self.result["wrappedAnchor"], "bottomleft")


if __name__ == "__main__":
    unittest.main()
