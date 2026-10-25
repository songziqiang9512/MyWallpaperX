"""User-selected videos through production preparation, frame gate and Metal draw."""

from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from script.tests import test_scene_material_video_asset as material
from script.tests import test_scene_user_property_textures as textures
from script.tests import test_scene_initial_video_resource_readiness as readiness
from script.tests.scene_video_segment_delegate_fixture import compile_segment_delegate

ROOT = Path(__file__).resolve().parents[2]
SCENE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene"


@unittest.skipUnless(shutil.which("swiftc") and shutil.which("ffmpeg"), "Swift and ffmpeg required")
class SceneUserPropertyVideoGPUTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix="mwx-user-property-video-")
        cls.addClassCleanup(cls.temporary.cleanup)
        cls.work = Path(cls.temporary.name)
        # Same production source group as SceneMaterialVideoAssetGPUTests,
        # plus the actual per-surface first-frame assembly owner.
        extras = [
            "Resources/Assets/SceneResourceIndex.swift", "Resources/Assets/SceneResourceView.swift",
            "Resources/Assets/SceneStockTextureSemanticRegistry.swift",
            "Resources/Textures/SceneTexturePathResolver.swift", "Resources/Textures/SceneMaterialAssetTextureCatalog.swift",
            "Resources/Textures/SceneBaseImageTextureCandidateSupport.swift", "Resources/Textures/SceneBaseMaterialTextureResolver.swift",
            "Compilation/Material/SceneBaseMaterialProviderBindingProgram.swift", "Compilation/Material/SceneEffectTextureInput.swift",
            "Compilation/Material/SceneRenderTargetVocabulary.swift",
            "Systems/Properties/SceneDynamicSnapshot.swift", "Rendering/Frame/SceneMetalRenderer+BaseMaterialColor.swift",
            "Rendering/Metal/SceneMetalPipeline.swift", "Runtime/Frame/SceneMaterialRenderState.swift", "Format/SceneWebMContainer.swift",
            "Rendering/Composition/SceneImageLayerDrawRequest.swift", "Rendering/Composition/SceneImageLayerCompositor+Uniforms.swift",
            "Rendering/Composition/SceneBlendModeShaderSource.swift",
            "Resources/Providers/SceneVideoPayloadPreparation.swift", "Resources/Providers/SceneVideoProviderLifecycleState.swift",
            "Resources/Providers/SceneVideoTextureSource.swift", "Resources/Providers/SceneVideoTextureSourceRegistry.swift",
            "Rendering/Composition/SceneFrameLayerTextureAssembly.swift",
        ]
        sources = list(dict.fromkeys(textures.SWIFT_SOURCES + [SCENE / path for path in extras]))
        # Reuse the existing real GPU draw helper, changing only its entry-point
        # name in this temporary compilation unit; no provider algorithm is copied.
        fixture = ROOT / "script/tests/fixtures/SceneMaterialVideoAssetHarness.swift"
        support = cls.work / "MaterialVideoFixtureSupport.swift"
        fixture_text = fixture.read_text()
        if fixture_text.count("@main enum Harness {") != 1:
            raise RuntimeError("material video fixture entry point changed")
        support.write_text(fixture_text.replace("@main enum Harness {", "enum MaterialVideoFixtureSupport {"))
        cls.environment = os.environ.copy()
        cls.environment["CLANG_MODULE_CACHE_PATH"] = str(cls.work / "clang-cache")
        home = cls.work / "home"
        home.mkdir()
        cls.environment.update(HOME=str(home), CFFIXED_USER_HOME=str(home))
        delegate_arguments = compile_segment_delegate(cls.work, environment=cls.environment)
        compiled = subprocess.run([
            "swiftc", "-parse-as-library", "-D", "DEBUG", "-default-isolation", "MainActor",
            *delegate_arguments, *map(str, sources), str(readiness.write_readiness_source(cls.work)), str(support),
            str(ROOT / "script/tests/fixtures/SceneUserPropertyVideoHarness.swift"),
            "-module-cache-path", str(cls.work / "swift-cache"), "-o", str(cls.work / "probe"),
        ], cwd=ROOT, env=cls.environment, capture_output=True, text=True, timeout=180)
        if compiled.returncode:
            raise RuntimeError(compiled.stderr)
        cls.shader = cls.work / "SceneImageLayer.metal"
        shader = SCENE / "Rendering/Composition/SceneImageLayer.metal"
        cls.shader.write_text(shader.read_text().replace('#include "SceneDistanceFog.metalh"',
            shader.with_name("SceneDistanceFog.metalh").read_text()))
        subprocess.run(["ffmpeg", "-v", "error", "-f", "lavfi", "-i",
            "color=red:size=32x24:rate=10:duration=1", "-f", "lavfi", "-i",
            "color=blue:size=32x24:rate=10:duration=1", "-filter_complex",
            "[0:v][1:v]concat=n=2:v=1:a=0", "-c:v", "libx264", "-pix_fmt", "yuv420p",
            str(cls.work / "clip.mp4")], check=True, capture_output=True, timeout=30)
        shutil.copyfile(cls.work / "clip.mp4", cls.work / "arbitrary-renamed.mp4")
        for extension in ["mov", "m4v"]:
            subprocess.run(["ffmpeg", "-v", "error", "-i", str(cls.work / "clip.mp4"),
                "-c", "copy", str(cls.work / f"remux.{extension}")],
                check=True, capture_output=True, timeout=30)
        subprocess.run(["ffmpeg", "-v", "error", "-f", "lavfi", "-i",
            "sine=frequency=440:duration=0.2", "-c:a", "aac", str(cls.work / "audio-only.mp4")],
            check=True, capture_output=True, timeout=30)
        (cls.work / "still.png").write_bytes(material.solid_png())
        (cls.work / "invalid.mp4").write_bytes(b"not a video container")

    def test_real_selected_video_frame_gate_lifecycle_and_gpu(self):
        run = subprocess.run([str(self.work / "probe"), str(self.work), str(self.shader)],
            cwd=ROOT, env=self.environment, capture_output=True, text=True, timeout=45)
        self.assertEqual(run.returncode, 0, run.stderr)
        result = json.loads(run.stdout)
        for variant in result["variants"]:
            with self.subTest(property=variant["property"]):
                self.assertTrue(variant["checks"])
                for name, passed in variant["checks"].items():
                    self.assertTrue(passed, (name, variant))
                self.assertGreater(variant["frames"], 10)
        for name, passed in result["rejections"].items():
            self.assertTrue(passed, (name, result))
        print(json.dumps(result, sort_keys=True))

    def test_external_video_publication_does_not_invent_authored_tex_format(self):
        run = subprocess.run([str(self.work / "probe"), str(self.work), str(self.shader), "--format-owner"],
            cwd=ROOT, env=self.environment, capture_output=True, text=True, timeout=20)
        self.assertEqual(run.returncode, 0, run.stderr)
        result = json.loads(run.stdout)
        print(json.dumps(result, sort_keys=True))
        self.assertEqual(len(result["rows"]), 2)
        for row in result["rows"]:
            with self.subTest(property=row["property"]):
                self.assertTrue(row["isComplete"] and row["generationIsCurrent"], row)
                self.assertIsNone(row["authoredFormat"], row)
