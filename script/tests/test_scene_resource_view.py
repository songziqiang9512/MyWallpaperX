#!/usr/bin/env python3

from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SWIFT_SOURCES = [
    SCENE_ROOT / "Resources/SceneResourceIndex.swift",
    SCENE_ROOT / "Resources/SceneResourceView.swift",
    SCENE_ROOT / "Resources/SceneTexturePathResolver.swift",
]

HARNESS = r'''
import Foundation

struct SceneRenderDescriptor {
    struct Layer {
        let imagePath: String?
    }

    struct ModelMaterialLink {
        let modelPath: String
        let materialPath: String?
    }

    struct MaterialPassDescriptor {
        let materialPath: String
        let texturePaths: [String]
    }

    let modelMaterialLinks: [ModelMaterialLink]
    let materialPasses: [MaterialPassDescriptor]
}

@main
enum Harness {
    static func main() throws {
        let package = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let loose = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        let stock = URL(fileURLWithPath: CommandLine.arguments[3], isDirectory: true)
        let view = SceneResourceView(
            projectRootURL: loose,
            packageRootURL: package,
            stockAssetsRootURL: stock
        )
        let descriptor = SceneRenderDescriptor(
            modelMaterialLinks: [
                .init(modelPath: "models/loose.json", materialPath: "materials/loose.json")
            ],
            materialPasses: [
                .init(materialPath: "materials/loose.json", texturePaths: ["loose"])
            ]
        )
        let resolver = SceneTexturePathResolver(resourceView: view, descriptor: descriptor)
        let layer = SceneRenderDescriptor.Layer(imagePath: "models/loose.json")
        let result: [String: Any] = [
            "duplicate": view.resource(relativePath: "materials/duplicate.tex")?.url.path ?? "missing",
            "loose": resolver.resolvePrimaryTexture(for: layer)?.path ?? "missing",
            "stock": resolver.resolveTextureFile(named: "stock")?.path ?? "missing",
            "explicitStock": view.resource(
                relativePath: "assets/models/util/solidlayer_depthtest.json"
            )?.url.path ?? "missing",
            "diagnosticSeesExplicitStock": view.availableRelativePaths.contains(
                "assets/models/util/solidlayer_depthtest.json"
            ),
            "trailingSpace": view.resource(
                relativePath: "materials/Album art 3  test .tex"
            )?.url.path ?? "missing",
            "trimmed": view.resource(
                relativePath: "materials/Album art 3  test.tex"
            )?.url.path ?? "missing",
            "escape": view.resource(relativePath: "../outside.tex")?.url.path ?? "missing",
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class SceneResourceViewTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-scene-resource-view-"
        )
        root = Path(cls.temporary_directory.name)
        cls.package = root / "package"
        cls.loose = root / "loose"
        cls.stock = root / "stock-assets"
        for directory in (cls.package, cls.loose, cls.stock):
            (directory / "materials").mkdir(parents=True)

        (cls.package / "materials/duplicate.tex").write_bytes(b"package")
        (cls.loose / "materials/duplicate.tex").write_bytes(b"loose")
        (cls.loose / "materials/loose.tex").write_bytes(b"loose")
        (cls.loose / "materials/Album art 3  test .tex").write_bytes(b"space")
        (cls.stock / "materials/stock.tex").write_bytes(b"stock")
        stock_model = cls.stock / "models/util/solidlayer_depthtest.json"
        stock_model.parent.mkdir(parents=True)
        stock_model.write_text("{}", encoding="utf-8")

        harness = root / "Harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        cls.binary = root / "scene-resource-view-harness"
        subprocess.run(
            [
                "xcrun", "--sdk", "macosx", "swiftc",
                *(str(path) for path in SWIFT_SOURCES),
                str(harness), "-o", str(cls.binary),
            ],
            cwd=REPOSITORY_ROOT,
            check=True,
            capture_output=True,
            text=True,
        )
        completed = subprocess.run(
            [str(cls.binary), str(cls.package), str(cls.loose), str(cls.stock)],
            check=True,
            capture_output=True,
            text=True,
        )
        cls.result = json.loads(completed.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_precedence_is_package_then_loose_then_stock(self) -> None:
        self.assertEqual(
            self.result["duplicate"],
            str((self.package / "materials/duplicate.tex").resolve()),
        )
        self.assertEqual(
            self.result["loose"],
            str((self.loose / "materials/loose.tex").resolve()),
        )
        self.assertEqual(
            self.result["stock"],
            str((self.stock / "materials/stock.tex").resolve()),
        )

    def test_stock_assets_prefix_maps_to_the_same_read_only_namespace(self) -> None:
        self.assertEqual(
            self.result["explicitStock"],
            str((self.stock / "models/util/solidlayer_depthtest.json").resolve()),
        )
        self.assertTrue(self.result["diagnosticSeesExplicitStock"])

    def test_file_identity_preserves_trailing_space_and_rejects_escape(self) -> None:
        self.assertEqual(
            self.result["trailingSpace"],
            str((self.loose / "materials/Album art 3  test .tex").resolve()),
        )
        self.assertEqual(self.result["trimmed"], "missing")
        self.assertEqual(self.result["escape"], "missing")


if __name__ == "__main__":
    unittest.main()
