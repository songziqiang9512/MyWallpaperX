#!/usr/bin/env python3

"""Production Metal execution for independent-signal composition."""

from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
sys.path.insert(0, str(REPOSITORY_ROOT / "script"))

from scene_swift_source_sets import scene_swift_sources  # noqa: E402


AUTHORED_SHADER_FRONTEND_SOURCES = scene_swift_sources(
    "authored_shader_frontend_core"
)
COLOR_CARRIER_ANALYZER_SOURCE = SCENE_ROOT / (
    "RenderGraph/ShaderFrontend/"
    "SceneAuthoredShaderIndependentSignalColorCarrierCompositingAnalyzer.swift"
)
SWIFT_SOURCES = [
    *AUTHORED_SHADER_FRONTEND_SOURCES,
    *(
        []
        if COLOR_CARRIER_ANALYZER_SOURCE in AUTHORED_SHADER_FRONTEND_SOURCES
        else [COLOR_CARRIER_ANALYZER_SOURCE]
    ),
    *scene_swift_sources("shader_variant_environment"),
    SCENE_ROOT / "RenderGraph/AuthoredGraph/SceneAuthoredEffectRenderPlan.swift",
    SCENE_ROOT / "RenderGraph/SceneMaterialRenderState.swift",
    SCENE_ROOT / "Resources/SceneTextureSampling.swift",
    SCENE_ROOT / "Resources/SceneTextureUVTransform.swift",
    SCENE_ROOT / "Resources/SceneTextureCandidate.swift",
    SCENE_ROOT / "Resources/SceneTextureSlotBinding.swift",
    SCENE_ROOT / "Resources/SceneNamedTextureReference.swift",
    SCENE_ROOT / "Resources/SceneTextureProviderPublication.swift",
    *scene_swift_sources("resolved_material_program_model"),
    SCENE_ROOT
    / "RenderGraph/EffectExecution/SceneResolvedMaterialAttachmentKind.swift",
    SCENE_ROOT
    / "RenderGraph/EffectExecution/SceneResolvedMaterialAttachmentStorage.swift",
    SCENE_ROOT
    / "RenderGraph/EffectExecution/SceneResolvedMaterialPassEncoder+Failure.swift",
    SCENE_ROOT
    / "RenderGraph/EffectExecution/SceneResolvedMaterialPassEncoder+Warmup.swift",
    SCENE_ROOT
    / "RenderGraph/EffectExecution/SceneResolvedMaterialPassEncoder.swift",
]
HARNESS = (
    REPOSITORY_ROOT
    / "script/tests/fixtures/SceneIndependentSignalCompositingGPUHarness.swift"
)


@unittest.skipUnless(shutil.which("swiftc"), "swiftc is required")
class SceneIndependentSignalCompositingGPUTests(unittest.TestCase):
    def test_signal_and_renamed_color_carriers_execute_with_local_rejections(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory(
            prefix="mwx-independent-signal-composite-gpu-"
        ) as directory:
            root = Path(directory)
            binary = root / "independent-signal-composite-gpu"
            environment = os.environ.copy()
            environment["CLANG_MODULE_CACHE_PATH"] = str(root / "clang-cache")
            environment["SWIFT_MODULECACHE_PATH"] = str(root / "swift-cache")
            compilation = subprocess.run(
                [
                    "xcrun",
                    "--sdk",
                    "macosx",
                    "swiftc",
                    "-parse-as-library",
                    *(str(path) for path in SWIFT_SOURCES),
                    str(HARNESS),
                    "-framework",
                    "Metal",
                    "-framework",
                    "CoreGraphics",
                    "-module-cache-path",
                    str(root / "module-cache"),
                    "-o",
                    str(binary),
                ],
                cwd=REPOSITORY_ROOT,
                env=environment,
                capture_output=True,
                text=True,
            )
            self.assertEqual(compilation.returncode, 0, compilation.stderr)
            completed = subprocess.run(
                [str(binary)],
                cwd=REPOSITORY_ROOT,
                env=environment,
                capture_output=True,
                text=True,
            )
            self.assertEqual(completed.returncode, 0, completed.stderr)
        payload = json.loads(completed.stdout)
        if not payload["metalAvailable"]:
            self.skipTest("Metal is unavailable")
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


if __name__ == "__main__":
    unittest.main()
