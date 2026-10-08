#!/usr/bin/env python3

"""Production Metal execution for independent-signal composition."""

from __future__ import annotations

import json
import hashlib
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
sys.path.insert(0, str(REPOSITORY_ROOT / "script"))

from scene_swift_source_sets import scene_swift_sources  # noqa: E402
from script.tests.test_scene_generic_shader_program_artifact import (  # noqa: E402
    SWIFT_SOURCES as GENERIC_SHADER_SOURCES,
)
from script.tests.test_scene_generic_shader_texture_transform_compiler import (  # noqa: E402
    compiler_bundle,
)


AUTHORED_SHADER_FRONTEND_SOURCES = scene_swift_sources(
    "authored_shader_frontend_core"
)
COLOR_CARRIER_ANALYZER_SOURCE = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/ShaderFrontend/SceneAuthoredShaderIndependentSignalColorCarrierCompositingAnalyzer.swift"
SWIFT_SOURCES = [
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Diagnostics/ScenePerformanceCounterHub.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Diagnostics/SceneGPUCensus.swift",
    *AUTHORED_SHADER_FRONTEND_SOURCES,
    *(
        []
        if COLOR_CARRIER_ANALYZER_SOURCE in AUTHORED_SHADER_FRONTEND_SOURCES
        else [COLOR_CARRIER_ANALYZER_SOURCE]
    ),
    *scene_swift_sources("shader_variant_environment"),
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Graph/SceneAuthoredEffectRenderPlan.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneMaterialRenderState.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureSampling.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureUVTransform.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureCandidate.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureSlotBinding.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneNamedTextureReference.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureProviderPublication.swift",
    *scene_swift_sources("resolved_material_program_model"),
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/SceneResolvedMaterialAttachmentKind.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/SceneResolvedMaterialAttachmentStorage.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/ScenePersistentCacheSupport.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/SceneResolvedMaterialPassEncoder+Failure.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/SceneResolvedMaterialPipelineBinaryArchive.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/SceneResolvedMaterialPassEncoder+Warmup.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/SceneResolvedMaterialPassEncoder.swift",
]
HARNESS = (
    REPOSITORY_ROOT
    / "script/tests/fixtures/SceneIndependentSignalCompositingGPUHarness.swift"
)
SWIFT_SOURCES = list(dict.fromkeys([*SWIFT_SOURCES, *GENERIC_SHADER_SOURCES]))


@unittest.skipUnless(shutil.which("swiftc"), "swiftc is required")
class SceneIndependentSignalCompositingGPUTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary = tempfile.TemporaryDirectory(
            prefix="mwx-independent-signal-composite-gpu-"
        )
        cls.addClassCleanup(cls.temporary.cleanup)
        root = Path(cls.temporary.name)
        # ArtifactCache uses Bundle.main. This CLI bundle carries the same real
        # signed compiler helpers used by the existing compiler GPU fixture.
        bundle = compiler_bundle(root)
        application = root / "BoundaryProbe.app"
        bundle.rename(application)
        contents = application / "Contents"
        executable = contents / "MacOS"
        executable.mkdir()
        binary = executable / "BoundaryProbe"
        info = plistlib.loads((contents / "Info.plist").read_bytes())
        info.update(CFBundleExecutable=binary.name, CFBundlePackageType="APPL")
        (contents / "Info.plist").write_bytes(plistlib.dumps(info))
        environment = os.environ.copy()
        for key in list(environment):
            if key.startswith("MWX_SCENE_GENERIC_SHADER_"):
                environment.pop(key)
        environment.update({
            "CLANG_MODULE_CACHE_PATH": str(root / "clang-cache"),
            "SWIFT_MODULECACHE_PATH": str(root / "swift-cache"),
            "MWX_SCENE_GENERIC_SHADER_CACHE": str(root / "artifacts"),
            "MWX_SCENE_GENERIC_SHADER_REQUESTS": str(root / "requests"),
            "HOME": str(root / "home"),
            "CFFIXED_USER_HOME": str(root / "home"),
        })
        for name in ("artifacts", "requests", "home"):
            (root / name).mkdir()
        inputs = [*SWIFT_SOURCES, HARNESS]
        before = {str(path): hashlib.sha256(path.read_bytes()).hexdigest()
                  for path in inputs}
        command = [
            "xcrun", "--sdk", "macosx", "swiftc", "-parse-as-library",
            *map(str, SWIFT_SOURCES), str(HARNESS),
            "-framework", "Metal", "-framework", "CoreGraphics",
            "-framework", "Security", "-module-cache-path",
            str(root / "module-cache"), "-o", str(binary),
        ]
        compilation = subprocess.run(command, cwd=REPOSITORY_ROOT,
            env=environment, capture_output=True, text=True, timeout=240)
        completed = None
        if compilation.returncode == 0:
            completed = subprocess.run([str(binary)], cwd=root, env=environment,
                capture_output=True, text=True, timeout=180)
        after = {str(path): hashlib.sha256(path.read_bytes()).hexdigest()
                 for path in inputs}
        evidence = os.environ.get("MWX_SCENE_GPU_TEST_EVIDENCE_DIR")
        if evidence:
            destination = Path(evidence)
            destination.mkdir(parents=True, exist_ok=True)
            (destination / "compile.log").write_text(compilation.stdout + compilation.stderr)
            (destination / "receipt.json").write_text(json.dumps({
                "command": command, "sourceSHA256": before,
                "sourcesUnchanged": before == after,
                "compileExitCode": compilation.returncode,
                "runExitCode": completed.returncode if completed else None,
            }, indent=2, sort_keys=True) + "\n")
            if completed:
                (destination / "result.json").write_text(completed.stdout)
                (destination / "run.log").write_text(completed.stderr)
        if before != after:
            raise RuntimeError("GPU fixture compilation inputs changed during execution")
        if compilation.returncode:
            raise RuntimeError(compilation.stderr)
        if completed.returncode:
            raise RuntimeError(completed.stderr or completed.stdout)
        cls.payload = json.loads(completed.stdout)
        if not cls.payload["metalAvailable"]:
            raise unittest.SkipTest("Metal is unavailable")

    def test_signal_and_renamed_color_carriers_execute_with_local_rejections(
        self,
    ) -> None:
        payload = self.payload
        self.assertEqual(
            [
                key
                for key in (
                    "signalCarrierFrontendAccepted",
                    "positiveAssembled",
                    "negativeRejected",
                    "encoded",
                    "completed",
                    "pixelsMatch",
                    "colorCarrierFrontendAccepted",
                    "colorCarrierAssembled",
                    "colorCarrierBadAlphaRejected",
                    "colorCarrierExtraReadRejected",
                    "colorCarrierEncoded",
                    "colorCarrierCompleted",
                    "colorCarrierPixelsMatch",
                )
                if not payload[key]
            ],
            [],
            payload,
        )

    def test_accepted_generic_and_bounded_programs_preserve_hdr_with_author_unorm(self) -> None:
        boundaries = self.payload["boundaries"]
        self.assertEqual(set(boundaries), {"preserving", "compositing", "authorUNorm"})
        transfers = {
            "preserving": "straightAlphaPreserving(textureSlot: 0)",
            "compositing": "independentAlphaSignalCompositing(signalSlot: 6, colorSlot: 2)",
            "authorUNorm": "straightAlphaUNorm(textureSlot: 0)",
        }
        cases = {
            "preserving": {"hdrOpaque", "hdrHalf", "sdrOpaque", "sdrHalf", "zeroAlpha"},
            "compositing": {"hdrOpaque", "hdrCoverage", "sdr", "zeroAlpha"},
            "authorUNorm": {"hdrOpaque", "hdrHalf", "sdr", "zeroAlpha"},
        }
        for name, result in boundaries.items():
            with self.subTest(profile=name):
                self.assertEqual(result["transfer"], transfers[name])
                self.assertEqual(result["boundedBackend"], "boundedSwift")
                self.assertEqual(result["inputFormat"], "rgba16Float")
                self.assertEqual(result["outputFormat"], "rgba16Float")
                backends = ("bounded",) if name == "authorUNorm" else ("generic", "bounded")
                if name == "authorUNorm":
                    self.assertNotIn("generic", result)
                else:
                    self.assertEqual(result["backend"], "genericCompilerArtifact")
                    self.assertEqual(result["routeState"], "generic-only")
                    self.assertEqual(len(result["requestKey"]), 64)
                    self.assertEqual(result["premultipliedColorInputSlots"], [])
                for backend in backends:
                    self.assertEqual(set(result[backend]), cases[name])
                    for case, frames in result[backend].items():
                        with self.subTest(backend=backend, case=case):
                            self.assertEqual(len(frames), 2)
                            self.assertEqual(frames[0]["bits"], frames[1]["bits"])
                            for frame in frames:
                                self.assertEqual(frame["completion"], "completed")
                                self.assertEqual(len(frame["output"]), 4)
                                for actual, expected in zip(frame["output"], frame["expected"]):
                                    self.assertAlmostEqual(actual, expected, delta=0.001)


if __name__ == "__main__":
    unittest.main()
