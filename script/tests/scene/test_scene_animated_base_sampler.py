#!/usr/bin/env python3

"""Focused contract for specialized TEX sampler propagation."""

from __future__ import annotations

import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
SCENE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SAMPLING_SOURCE = SCENE_ROOT / "Resources/Textures/SceneTextureSampling.swift"
LOAD_SOURCE = SCENE_ROOT / "Resources/Textures/SceneBaseImageTextureLoad.swift"
FRAME_ROOT = SCENE_ROOT / "Rendering/Frame"
REQUEST_SOURCE = SCENE_ROOT / "Rendering/Composition/SceneImageLayerDrawRequest.swift"


class SceneAnimatedBaseSamplerTests(unittest.TestCase):
    def test_specialized_sampler_reaches_draw_and_capture(self) -> None:
        load = LOAD_SOURCE.read_text(encoding="utf-8")
        view = (FRAME_ROOT / "SceneMetalView.swift").read_text(encoding="utf-8")
        request = REQUEST_SOURCE.read_text(encoding="utf-8")
        renderer = (FRAME_ROOT / "SceneMetalRenderer+ImageLayerEncoding.swift").read_text(encoding="utf-8")
        preflight = (FRAME_ROOT / "SceneResolvedMaterialFramePreflight.swift").read_text(encoding="utf-8")
        named = (FRAME_ROOT / "SceneMetalRenderer+DependencyProviders.swift").read_text(encoding="utf-8")

        self.assertIn("SceneTextureSampling(texFlags: container.flags)", load)
        self.assertIn("loadedSpecializedBaseTextureSamplings[layer.id] = sampling", view)
        self.assertIn("specializedBaseTextureSamplings[layerID] = loaded.baseTextureSampling", view)
        self.assertIn("for: baseTextureSampling ?? .linearClamp", request)
        self.assertIn(
            "baseTextureSampling: specializedBaseTextureSamplings[layer.id]",
            renderer,
        )
        self.assertIn(
            "baseTextureSampling: specializedBaseTextureSamplings[layerID]",
            preflight,
        )
        self.assertIn("spriteFrames: spriteFrames", view)
        self.assertIn("textureFrame: baseSource.spriteFrame?.textureFrame", renderer)
        self.assertIn("textureFrame = source.spriteFrame?.textureFrame", preflight)
        self.assertIn("spriteFrame: source?.spriteFrame", named)

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
