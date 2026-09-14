#!/usr/bin/env python3

"""Focused contract for specialized TEX sampler propagation."""

from __future__ import annotations

import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SAMPLING_SOURCE = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureSampling.swift"
LOAD_SOURCE = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneBaseImageTextureLoad.swift"
VIEW_SOURCE = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneMetalView.swift"
REQUEST_SOURCE = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Composition/SceneImageLayerDrawRequest.swift"
RENDERER_SOURCE = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneMetalRenderer.swift"
PREFLIGHT_SOURCE = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneResolvedMaterialFramePreflight.swift"
)


class SceneAnimatedBaseSamplerTests(unittest.TestCase):
    def test_specialized_sampler_reaches_both_request_builders(self) -> None:
        load = LOAD_SOURCE.read_text(encoding="utf-8")
        view = VIEW_SOURCE.read_text(encoding="utf-8")
        request = REQUEST_SOURCE.read_text(encoding="utf-8")
        renderer = RENDERER_SOURCE.read_text(encoding="utf-8")
        preflight = PREFLIGHT_SOURCE.read_text(encoding="utf-8")

        self.assertIn(
            "let baseTextureSampling: SceneTextureSampling?", load
        )
        self.assertIn(
            "SceneTextureSampling(texFlags: container.flags)", load
        )
        self.assertIn(
            "var specializedBaseTextureSamplings: [Int: SceneTextureSampling]",
            view,
        )
        self.assertIn(
            "loadedSpecializedBaseTextureSamplings[layer.id] = sampling",
            view,
        )
        self.assertIn(
            "specializedBaseTextureSamplings[layerID] = loaded.baseTextureSampling",
            view,
        )
        self.assertIn(
            "for: baseTextureSampling ?? .linearClamp",
            request,
        )
        self.assertIn(
            "specializedBaseTextureSamplings: [Int: SceneTextureSampling]",
            renderer,
        )
        self.assertIn(
            "baseTextureSampling: specializedBaseTextureSamplings[layer.id]",
            renderer,
        )
        self.assertIn(
            "baseTextureSampling: specializedBaseTextureSamplings[layerID]",
            preflight,
        )

    def test_tex_flags_compile_to_the_shared_sampler_modes(self) -> None:
        harness = r"""
import Metal

@main
enum Harness {
    static func main() {
        let flags: [UInt32] = [0, 1, 2, 3, 4, 6, 7]
        print(flags.map {
            SceneTextureSampling(texFlags: $0).imageLayerUniformMode
        }.map(String.init).joined(separator: ","))
    }
}
"""
        with tempfile.TemporaryDirectory(prefix="mwx-specialized-sampler-") as raw:
            directory = Path(raw)
            harness_path = directory / "Harness.swift"
            binary = directory / "harness"
            harness_path.write_text(harness, encoding="utf-8")
            result = subprocess.run(
                [
                    "xcrun",
                    "--sdk",
                    "macosx",
                    "swiftc",
                    str(SAMPLING_SOURCE),
                    str(harness_path),
                    "-framework",
                    "Metal",
                    "-o",
                    str(binary),
                ],
                capture_output=True,
                text=True,
                check=False,
            )
            if result.returncode != 0:
                self.fail(
                    "sampler harness failed to compile:\n"
                    + result.stdout
                    + result.stderr
                )
            run = subprocess.run(
                [str(binary)], capture_output=True, text=True, check=False
            )
            self.assertEqual(run.returncode, 0, run.stderr)
            self.assertEqual(run.stdout.strip(), "1,3,0,2,1,0,2")


if __name__ == "__main__":
    unittest.main()
