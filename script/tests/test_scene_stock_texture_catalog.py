#!/usr/bin/env python3

from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPT_DIR))

import generate_scene_stock_texture_catalog as generator


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
BUNDLE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Resources/SceneStockTextures.bundle"
PLACEHOLDER = (
    REPOSITORY_ROOT
    / "MyWallpaperX/Assets.xcassets/AppIcon.appiconset/Icon-iOS-Dark-16x16@1x.png"
)


class SceneStockTextureCatalogTests(unittest.TestCase):
    def test_generator_preserves_identity_without_copying_tex_payload(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-stock-textures-") as directory:
            root = Path(directory)
            source = root / "wallpaper_engine"
            (source / "assets/materials/particle/fire").mkdir(parents=True)
            (source / "assets/materials/util").mkdir(parents=True)
            (source / "version.json").write_text('{"version":"2.8.42"}')
            fire = source / "assets/materials/particle/fire/fire1.tex"
            white = source / "assets/materials/util/white.tex"
            fire.write_bytes(b"official-fire-payload")
            white.write_bytes(b"official-white-payload")
            Path(f"{fire}-json").write_text('{"format":"r8"}')
            output = root / "SceneStockTextures.bundle"

            catalog = generator.build_catalog(source, PLACEHOLDER, output, "23967692")

            self.assertEqual(catalog["texture_count"], 2)
            self.assertEqual(catalog["wallpaper_engine_version"], "2.8.42")
            self.assertEqual(catalog["category_counts"], {
                "assets/materials/particle": 1,
                "assets/materials/util": 1,
            })
            self.assertTrue(catalog["textures"][0]["official_sidecar_present"])
            self.assertFalse(catalog["textures"][1]["official_sidecar_present"])
            self.assertEqual(
                (output / "assets/materials/particle/fire/fire1.png").read_bytes(),
                PLACEHOLDER.read_bytes(),
            )
            self.assertNotIn(b"official-fire-payload", b"".join(
                path.read_bytes() for path in output.rglob("*.png")
            ))

    def test_checked_in_catalog_matches_the_bundled_placeholder_tree(self) -> None:
        catalog = json.loads(
            (BUNDLE_ROOT / "texture-catalog.json").read_text(encoding="utf-8")
        )
        self.assertEqual(catalog["schema_version"], 1)
        self.assertEqual(catalog["wallpaper_engine_version"], "2.8.42")
        self.assertEqual(catalog["steam_build_id"], "23967692")
        self.assertEqual(catalog["texture_count"], 311)
        self.assertEqual(catalog["category_counts"]["assets/materials/particle"], 164)
        self.assertFalse(catalog["mapping"]["runtime_consumed"])
        placeholder_hash = generator.sha256(BUNDLE_ROOT / "placeholder.png")
        self.assertEqual(catalog["placeholder_sha256"], placeholder_hash)

        project_paths = [entry["project_path"] for entry in catalog["textures"]]
        self.assertEqual(len(project_paths), len(set(project_paths)))
        self.assertIn("assets/materials/particle/fire/fire1.png", project_paths)
        self.assertIn("assets/materials/lut/neutral.png", project_paths)
        for path in project_paths:
            candidate = BUNDLE_ROOT / path
            self.assertTrue(candidate.is_file(), path)
            self.assertEqual(generator.sha256(candidate), placeholder_hash, path)


if __name__ == "__main__":
    unittest.main()
