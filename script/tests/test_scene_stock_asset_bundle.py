#!/usr/bin/env python3

from __future__ import annotations

import hashlib
import sys
import tempfile
import unittest
from collections import Counter
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPT_DIR))

import generate_scene_stock_asset_bundle as generator


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
BUNDLE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Resources/SceneStockAssets.bundle"
PLACEHOLDER = (
    REPOSITORY_ROOT
    / "MyWallpaperX/Assets.xcassets/AppIcon.appiconset/Icon-iOS-Dark-16x16@1x.png"
)
OFFICIAL_FONT_NAMES = {
    "8bitOperatorPlus8-Regular.ttf",
    "Alcubierre.otf",
    "Atami-Regular.otf",
    "Blackout 2 AM.ttf",
    "CursedTimerUlil-Aznm.ttf",
    "Lazer84.ttf",
    "Monofur-PK7og.ttf",
    "NotoSans-Regular.ttf",
    "RobotoMono-Regular.ttf",
    "Segment7Standard.otf",
    "TwemojiMozilla.ttf",
    "kust.ttf",
    "opensticks.ttf",
    "spincycle_3d_ot.otf",
    "summer85.ttf",
}


class SceneStockAssetBundleTests(unittest.TestCase):
    def test_generator_includes_playback_candidates_and_excludes_editor_assets(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-stock-assets-") as directory:
            root = Path(directory)
            source = root / "wallpaper_engine"
            assets = source / "assets"
            fonts = root / "font-placeholders"
            fonts.mkdir(parents=True)
            (fonts / "Atami-Regular.otf").write_bytes(b"licensed-font-placeholder")

            included = {
                "materials/particle/fire/fire1.tex": b"official-fire-payload",
                "materials/particle/fire/fire1.tex-json": b'{"format":"r8"}',
                "materials/util/white.tex": b"official-white-payload",
                "effects/waterflow/effect.json": b'{"official":true}',
                "effects/waterflow/shaders/effects/waterflow.frag": b"official shader",
                "effects/waterflow/materials/effects/waterflowphase.png": b"official png",
                "fonts/Atami-Regular.otf": b"official-font-payload",
                "models/util/solidlayer.json": b'{"official":true}',
                "scripts/jsmodules/wemath.js": b"official js",
                "zcompat/web/123.json": b'{"official":true}',
            }
            excluded = {
                "materials/util/white.png": b"compiled source",
                "effects/waterflow/preview/materials/effectpreview.tex": b"preview",
                "presets/fire/preset.json": b"preset",
                "scenes/gifs/scene.json": b"scene fixture",
                "particles/example.json": b"example",
                "materials/editor/brush.json": b"editor",
                "materials/particle/fire/fire_preview.gif": b"preview gif",
                "fonts/license.txt": b"license",
                "materials/util/webthumbnailfallback.png": b"thumbnail",
            }
            for relative, data in {**included, **excluded}.items():
                path = assets / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(data)

            output = root / "SceneStockAssets.bundle"
            summary = generator.build_bundle(source, PLACEHOLDER, fonts, output)

            self.assertEqual(summary["runtime_asset_count"], len(included))
            self.assertEqual(summary["excluded_asset_count"], len(excluded))
            output_paths = {
                path.relative_to(output / "assets").as_posix()
                for path in (output / "assets").rglob("*")
                if path.is_file()
            }
            self.assertEqual(output_paths, set(included))
            self.assertFalse(any(output.glob("*catalog*")))
            self.assertEqual(
                (output / "assets/fonts/Atami-Regular.otf").read_bytes(),
                b"licensed-font-placeholder",
            )
            self.assertNotIn(
                b"official-fire-payload",
                b"".join(path.read_bytes() for path in output.rglob("*.tex")),
            )

    def test_checked_in_bundle_is_the_locked_playback_placeholder_set(self) -> None:
        assets_root = BUNDLE_ROOT / "assets"
        paths = sorted(path for path in assets_root.rglob("*") if path.is_file())
        self.assertEqual(len(paths), 919)
        counts = Counter(generator.asset_extension(path) for path in paths)
        self.assertEqual(counts, {
            ".frag": 125,
            ".geom": 4,
            ".h": 14,
            ".js": 4,
            ".json": 208,
            ".otf": 4,
            ".png": 3,
            ".tex": 223,
            ".tex-json": 198,
            ".ttf": 11,
            ".vert": 125,
        })
        self.assertFalse((BUNDLE_ROOT / "asset-catalog.json").exists())
        self.assertFalse((BUNDLE_ROOT / "texture-catalog.json").exists())

        for required in [
            "effects/refraction/effect.json",
            "effects/refraction/materials/effects/refractnormal.png",
            "materials/lut/neutral.tex",
            "materials/particle/fire/fire1.tex",
            "materials/util/composelayer.json",
            "models/util/solidlayer.json",
            "scripts/jsmodules/wemath.js",
            "shaders/genericparticle.vert",
            "zcompat/web/780658164.json",
        ]:
            self.assertTrue((assets_root / required).is_file(), required)

        relative_paths = [path.relative_to(assets_root).as_posix() for path in paths]
        self.assertFalse(any(path.startswith(("presets/", "scenes/", "particles/")) for path in relative_paths))
        self.assertFalse(any("/preview" in f"/{path.lower()}" for path in relative_paths))
        self.assertFalse(any("/editor/" in f"/{path.lower()}/" for path in relative_paths))
        self.assertFalse(any(path.lower().endswith("_preview.gif") for path in relative_paths))

        font_names = {path.name for path in (assets_root / "fonts").iterdir()}
        self.assertEqual(font_names, OFFICIAL_FONT_NAMES)
        self.assertFalse({
            "Bangers-Regular.ttf",
            "BungeeShade-Regular.ttf",
            "PermanentMarker-Regular.ttf",
            "Poppins-ExtraLight.ttf",
            "Poppins-Medium.ttf",
        } & font_names)
        self.assertEqual(
            (assets_root / "fonts/summer85.ttf").read_bytes(),
            (assets_root / "fonts/Lazer84.ttf").read_bytes(),
        )
        self.assertEqual(
            (assets_root / "fonts/CursedTimerUlil-Aznm.ttf").read_bytes(),
            (assets_root / "fonts/Segment7Standard.otf").read_bytes(),
        )

        placeholder_tex_hash = hashlib.sha256(
            generator.placeholder_tex_bytes(PLACEHOLDER.read_bytes())
        ).hexdigest()
        self.assertEqual(
            {hashlib.sha256(path.read_bytes()).hexdigest() for path in paths if path.suffix == ".tex"},
            {placeholder_tex_hash},
        )
        self.assertEqual(len(list((BUNDLE_ROOT / "Licenses").iterdir())), 9)
        self.assertTrue((BUNDLE_ROOT / "NOTICE.md").is_file())


if __name__ == "__main__":
    unittest.main()
