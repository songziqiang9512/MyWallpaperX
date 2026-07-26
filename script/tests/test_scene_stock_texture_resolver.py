#!/usr/bin/env python3

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
    / "MyWallpaperX/Core/SteamWorkshopScene/Resources/SceneStockTextureResolver.swift"
)
BUNDLE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Resources/SceneStockTextures.bundle"

HARNESS_SOURCE = r'''
import Foundation

@main
enum Harness {
    static func main() throws {
        let bundleRoot = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        guard let resolver = SceneStockTextureResolver(bundleRoot: bundleRoot) else {
            throw HarnessError.catalogUnavailable
        }
        let references = Array(CommandLine.arguments.dropFirst(2))
        var paths: [String: String] = [:]
        for reference in references {
            paths[reference] = resolver.textureURL(for: reference)?.path ?? "missing"
        }
        let data = try JSONSerialization.data(withJSONObject: paths, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }

    private enum HarnessError: Error {
        case catalogUnavailable
    }
}
'''


class SceneStockTextureResolverTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        swiftc = shutil.which("swiftc")
        if swiftc is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(prefix="mwx-stock-resolver-")
        directory = Path(cls.temporary_directory.name)
        harness = directory / "Harness.swift"
        harness.write_text(HARNESS_SOURCE, encoding="utf-8")
        cls.binary = directory / "scene-stock-texture-resolver"
        subprocess.run(
            [swiftc, str(SOURCE), str(harness), "-o", str(cls.binary)],
            check=True,
            capture_output=True,
            text=True,
        )

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def run_harness(self, references: list[str]) -> dict[str, str]:
        completed = subprocess.run(
            [str(self.binary), str(BUNDLE_ROOT), *references],
            check=True,
            capture_output=True,
            text=True,
        )
        return json.loads(completed.stdout)

    def test_catalog_aliases_resolve_to_exact_png_paths(self) -> None:
        references = [
            "particle/fire/fire1",
            r"Materials\Particle\Fire\Fire1.TEX",
            "assets/materials/particle/fire/fire1.png",
            "materials/lut/neutral.tex",
            "effects/waterflow/preview/materials/effects/waterflowphase",
        ]
        paths = self.run_harness(references)
        fire = str(BUNDLE_ROOT / "assets/materials/particle/fire/fire1.png")
        self.assertEqual(paths["particle/fire/fire1"], fire)
        self.assertEqual(paths[r"Materials\Particle\Fire\Fire1.TEX"], fire)
        self.assertEqual(paths["assets/materials/particle/fire/fire1.png"], fire)
        self.assertEqual(
            paths["materials/lut/neutral.tex"],
            str(BUNDLE_ROOT / "assets/materials/lut/neutral.png"),
        )
        self.assertEqual(
            paths["effects/waterflow/preview/materials/effects/waterflowphase"],
            str(
                BUNDLE_ROOT
                / "assets/effects/waterflow/preview/materials/effects/waterflowphase.png"
            ),
        )

    def test_all_catalog_official_paths_resolve_to_project_pngs(self) -> None:
        catalog = json.loads((BUNDLE_ROOT / "texture-catalog.json").read_text())
        references = [entry["official_path"] for entry in catalog["textures"]]
        paths = self.run_harness(references)
        self.assertEqual(len(paths), 311)
        for entry in catalog["textures"]:
            self.assertEqual(
                paths[entry["official_path"]],
                str(BUNDLE_ROOT / entry["project_path"]),
            )

    def test_missing_and_unsafe_references_fail_closed(self) -> None:
        references = [
            "particle/not-present",
            "../assets/materials/particle/fire/fire1.tex",
        ]
        paths = self.run_harness(references)
        self.assertEqual(paths["particle/not-present"], "missing")
        self.assertEqual(
            paths["../assets/materials/particle/fire/fire1.tex"],
            "missing",
        )


if __name__ == "__main__":
    unittest.main()
