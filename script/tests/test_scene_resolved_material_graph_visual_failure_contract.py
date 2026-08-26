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
RESOURCE_ENCODER_SOURCE = SCENE_ROOT / (
    "RenderGraph/EffectExecution/SceneGraphResourcePassEncoder.swift"
)
EXECUTOR_SOURCE = SCENE_ROOT / (
    "RenderGraph/EffectExecution/SceneResolvedMaterialGraphExecutor.swift"
)
PROGRAM_FIRST_STAGES_SOURCE = SCENE_ROOT / (
    "RenderGraph/EffectExecution/SceneResolvedMaterialExecutionCapability+ProgramFirstStages.swift"
)
VISUAL_FAILURE_TOPOLOGY_SOURCE = SCENE_ROOT / (
    "RenderGraph/EffectExecution/SceneResolvedMaterialVisualFailureTopology.swift"
)
VISUAL_FAILURE_PASSTHROUGH_SOURCE = SCENE_ROOT / (
    "RenderGraph/EffectExecution/SceneResolvedMaterialGraphExecutor+VisualFailurePassthrough.swift"
)
SWIFT_SOURCES = [
    *PUBLICATION_FIXTURE["SWIFT_SOURCES"],
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
    RESOURCE_ENCODER_SOURCE,
    SCENE_ROOT / "RenderGraph/GraphTargets/SceneOffscreenResolutionPolicy.swift",
    SCENE_ROOT / "RenderGraph/AuthoredGraph/SceneGraphConditionAdmission.swift",
    SCENE_ROOT / "RenderGraph/AuthoredGraph/SceneGraphAdmissionCompiler.swift",
    SCENE_ROOT
    / "RenderGraph/EffectExecution/SceneResolvedMaterialExecutionCapabilityAdmission.swift",
    SCENE_ROOT
    / "RenderGraph/EffectExecution/SceneResolvedMaterialExecutionCapability+DependencyOwnership.swift",
    SCENE_ROOT
    / "RenderGraph/EffectExecution/SceneResolvedMaterialExecutionCapability.swift",
    SCENE_ROOT
    / "RenderGraph/EffectExecution/SceneResolvedMaterialExecutionCapability+Material.swift",
    SCENE_ROOT
    / "RenderGraph/EffectExecution/SceneResolvedMaterialExecutionCapability+PipelineWarmup.swift",
    SCENE_ROOT
    / "RenderGraph/EffectExecution/SceneResolvedMaterialExecutionCapability+PreservedChannels.swift",
    SCENE_ROOT
    / "RenderGraph/EffectExecution/SceneResolvedMaterialExecutionCapability+Stages.swift",
    SCENE_ROOT
    / "RenderGraph/EffectExecution/SceneResolvedMaterialStageActivation.swift",
    PROGRAM_FIRST_STAGES_SOURCE,
    VISUAL_FAILURE_TOPOLOGY_SOURCE,
    SCENE_ROOT
    / "RenderGraph/EffectExecution/SceneResolvedMaterialExecutionCapabilityTemplateAdmission.swift",
    SCENE_ROOT
    / "RenderGraph/EffectExecution/SceneResolvedMaterialExecutionCapability+EnvelopeDiagnostics.swift",
    EXECUTOR_SOURCE,
    SCENE_ROOT
    / "RenderGraph/EffectExecution/SceneResolvedMaterialGraphExecutor+Attachment.swift",
    SCENE_ROOT
    / "RenderGraph/EffectExecution/SceneResolvedMaterialGraphExecutor+Preparation.swift",
    VISUAL_FAILURE_PASSTHROUGH_SOURCE,
    SCENE_ROOT
    / "RenderGraph/EffectExecution/SceneResolvedMaterialGraphExecutor+DedicatedPreparation.swift",
    SCENE_ROOT
    / "RenderGraph/EffectExecution/SceneResolvedMaterialGraphExecutor+Validation.swift",
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
        for reason in (
            "material-finalizer-dynamic-uniform-binding",
            "material-finalizer-static-uniform-binding",
            "material-finalizer-host-uniform-declaration-conflict",
            "material-finalizer-uniform-declaration-conflict",
            "material-finalizer-optional-texture-unavailable",
            "material-finalizer-optional-texture-purpose-mismatch",
            "material-finalizer-optional-texture-content-mismatch",
            "material-finalizer-optional-texture-sampling-unresolved",
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
