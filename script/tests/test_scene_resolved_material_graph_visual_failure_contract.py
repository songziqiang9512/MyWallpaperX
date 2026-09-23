#!/usr/bin/env python3

"""Shared source set and fail-soft contract for the material graph GPU gate."""

from __future__ import annotations

import os
from pathlib import Path
import runpy
import shutil
import subprocess
import tempfile
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
PUBLICATION_GATE = Path(__file__).with_name(
    "test_scene_graph_texture_publication.py"
)
MAIN_GATE = Path(__file__).with_name(
    "test_scene_resolved_material_graph_executor.py"
)
PUBLICATION_FIXTURE = runpy.run_path(str(PUBLICATION_GATE))
RESOURCE_ENCODER_SOURCE = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/SceneGraphResourcePassEncoder.swift"
EXECUTOR_SOURCE = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/SceneResolvedMaterialGraphExecutor.swift"
PROGRAM_FIRST_STAGES_SOURCE = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneResolvedMaterialExecutionCapability+ProgramFirstStages.swift"
PROGRAM_FIRST_STAGES_INPUT_CONTRACTS_SOURCE = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneResolvedMaterialExecutionCapability+ProgramFirstStages+InputContracts.swift"
PROGRAM_FIRST_STAGES_BACKGROUND_SOURCE = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneResolvedMaterialExecutionCapability+ProgramFirstStagesBackground.swift"
VISUAL_FAILURE_TOPOLOGY_SOURCE = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneResolvedMaterialVisualFailureTopology.swift"
VISUAL_FAILURE_PASSTHROUGH_SOURCE = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/SceneResolvedMaterialGraphExecutor+VisualFailurePassthrough.swift"
SWIFT_SOURCES = [
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Diagnostics/ScenePerformanceCounterHub.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Diagnostics/SceneGPUCensus.swift",
    *PUBLICATION_FIXTURE["SWIFT_SOURCES"],
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/SceneResolvedMaterialAttachmentKind.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/SceneResolvedMaterialAttachmentStorage.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/SceneResolvedMaterialPassEncoder+Failure.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/SceneResolvedMaterialPassEncoder+Warmup.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/SceneResolvedMaterialPassEncoder.swift",
    RESOURCE_ENCODER_SOURCE,
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Targets/SceneOffscreenResolutionPolicy.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Graph/SceneGraphConditionAdmission.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Graph/SceneGraphAdmissionCompiler.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneResolvedMaterialExecutionCapabilityAdmission.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneDirectBoolEffectVisibilityRouteAdmission.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneResolvedMaterialExecutionCapability+DependencyOwnership.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/ScenePreparedDirectDrawOutputGeometry.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneResolvedMaterialDirectDrawGeometryCompiler.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneResolvedMaterialExecutionCapability.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneResolvedMaterialExecutionCapability+DynamicUniformRejection.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneResolvedMaterialExecutionCapability+Material.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneResolvedMaterialExecutionCapability+PipelineWarmup.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneResolvedMaterialExecutionCapability+PreservedChannels.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneResolvedMaterialExecutionCapability+Stages.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/SceneResolvedMaterialStageActivation.swift",
    PROGRAM_FIRST_STAGES_SOURCE,
    PROGRAM_FIRST_STAGES_INPUT_CONTRACTS_SOURCE,
    PROGRAM_FIRST_STAGES_BACKGROUND_SOURCE,
    VISUAL_FAILURE_TOPOLOGY_SOURCE,
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneResolvedMaterialExecutionCapabilityTemplateAdmission.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneResolvedMaterialExecutionCapability+EnvelopeDiagnostics.swift",
    EXECUTOR_SOURCE,
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/SceneResolvedMaterialGraphExecutor+Attachment.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/SceneResolvedMaterialGraphExecutor+Preparation.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/SceneResolvedMaterialGraphExecutor+DynamicUniformDiagnostics.swift",
    VISUAL_FAILURE_PASSTHROUGH_SOURCE,
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/SceneResolvedMaterialGraphExecutor+Validation.swift",
]


def compile_harness(support_text: str, harness_text: str):
    with tempfile.TemporaryDirectory(
        prefix="mwx-resolved-material-graph-executor-"
    ) as directory:
        root = Path(directory)
        support = root / "Support.swift"
        harness = root / "Harness.swift"
        binary = root / "resolved-material-graph-executor-test"
        support.write_text(support_text, encoding="utf-8")
        harness.write_text(harness_text, encoding="utf-8")
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
                "-D",
                "SCENE_GRAPH_TESTING",
                str(support),
                *(str(path) for path in SWIFT_SOURCES),
                str(harness),
                "-framework",
                "Metal",
                "-framework",
                "CoreGraphics",
                "-framework",
                "ImageIO",
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
        if compilation.returncode != 0:
            return compilation, None
        completed = subprocess.run(
            [str(binary)],
            cwd=REPOSITORY_ROOT,
            env=environment,
            capture_output=True,
            text=True,
        )
        return compilation, completed


@unittest.skipUnless(shutil.which("swiftc"), "swiftc is required")
class SceneResolvedMaterialGraphVisualFailureContractTests(unittest.TestCase):
    def test_visual_failure_passthrough_keeps_exact_reason_allowlist(self) -> None:
        for source in (
            PROGRAM_FIRST_STAGES_SOURCE,
            VISUAL_FAILURE_PASSTHROUGH_SOURCE,
        ):
            text = source.read_text(encoding="utf-8")
            for reason in (
                "material-variant-envelope-frontend",
                "material-variant-envelope-shader-preparation",
                "material-generic-owner-revoked",
                "material-variant-envelope-color-contract",
                "material-variant-envelope-uniform-schema",
            ):
                self.assertIn(f'"{reason}"', text)
            for reason in (
                "material-variant-envelope-texture",
                "material-variant-envelope-target",
                "material-variant-envelope-runtime-encode",
            ):
                self.assertNotIn(f'"{reason}"', text)
        visual_text = VISUAL_FAILURE_PASSTHROUGH_SOURCE.read_text(encoding="utf-8")
        self.assertIn(
            'reasonCode != "material-finalizer-color-contract"',
            visual_text,
        )
        self.assertIn("graph.renderTargets.isEmpty", visual_text)
        for reason in (
            "material-finalizer-dynamic-uniform-binding",
            "material-finalizer-static-uniform-binding",
            "material-finalizer-host-uniform-declaration-conflict",
            "material-finalizer-uniform-declaration-conflict",
            "material-finalizer-color-contract",
            "material-finalizer-optional-texture-unavailable",
            "material-finalizer-optional-texture-purpose-mismatch",
            "material-finalizer-optional-texture-content-mismatch",
            "material-finalizer-optional-texture-sampling-unresolved",
            "material-finalizer-system-provider-pending",
            "material-finalizer-system-provider-unavailable",
            "material-finalizer-system-provider-purpose-mismatch",
            "material-finalizer-system-provider-sampling-unresolved",
            "material-dynamic-uniform-contributor-policy",
            "material-dynamic-uniform-contributor-producer-unavailable",
            "material-dynamic-uniform-script-attachment-unproven",
            "material-dynamic-uniform-producer-unavailable",
        ):
            self.assertIn(f'"{reason}"', visual_text)
        for reason in (
            "material-finalizer-resource",
            "material-finalizer-texture",
            "material-finalizer-host-uniform-binding",
            "material-finalizer-active-uniform-schema",
        ):
            self.assertNotIn(f'"{reason}"', visual_text)
        self.assertNotIn(
            "SceneOffscreenEffectRenderer",
            EXECUTOR_SOURCE.read_text(encoding="utf-8"),
        )
        self.assertNotIn(
            "SceneOffscreenEffectRenderer",
            MAIN_GATE.read_text(encoding="utf-8"),
        )


if __name__ == "__main__":
    unittest.main()
