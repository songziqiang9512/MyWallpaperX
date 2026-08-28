"""Static owner assertions for the shared Program-first stage path."""

from __future__ import annotations

from pathlib import Path
from typing import Any


def assert_authored_material_families_use_program_first_pair_adapters(
    test_case: Any,
    *,
    scene_root: Path,
    effect_backend_source: Path,
    capability_source: Path,
    capability_stages_source: Path,
    capability_program_first_source: Path,
) -> None:
    source = effect_backend_source.read_text(encoding="utf-8")
    leaf_start = source.index("        var supportsUnifiedPairLeaf: Bool")
    logical_start = source.index(
        "    nonisolated var supportsUnifiedLogicalTargetStage: Bool"
    )
    leaf_body = source[leaf_start:logical_start]
    logical_end = source.index("\n    nonisolated var standardBlur:", logical_start)
    logical_body = source[logical_start:logical_end]

    test_case.assertNotIn(".pulse", source)
    test_case.assertNotIn(".xRay", source)
    test_case.assertNotIn(".blend", leaf_body)
    test_case.assertNotIn(".waterWaves", leaf_body)
    test_case.assertNotIn(".waterFlow", source)
    test_case.assertNotIn("yieldsToResolvedMaterialProgram", source)
    test_case.assertNotIn(".lightShafts", leaf_body)
    test_case.assertNotIn("proceduralNoise", leaf_body)
    test_case.assertNotIn(".spin", source)
    test_case.assertNotIn(".workshopAudioBars", leaf_body)
    test_case.assertNotIn("fisheyeZeroDistortion", leaf_body)
    test_case.assertIn("case .standardBlur:", logical_body)
    test_case.assertNotIn("preciseGaussian", source)
    test_case.assertNotIn("case .localContrast:", logical_body)
    test_case.assertNotIn("case .godrays", logical_body)
    dedicated_compilers = (
        scene_root
        / "RenderGraph/EffectCompilation/SceneEffectStageDedicatedCompilers.swift"
    ).read_text(encoding="utf-8")
    test_case.assertNotIn("SceneAuthoredGodraysPlanner", dedicated_compilers)
    test_case.assertNotIn("SceneAuthoredWaterWavesPlanner", dedicated_compilers)
    test_case.assertNotIn(
        "stock-radial-owner-revoked-to-material-program",
        dedicated_compilers,
    )
    test_case.assertNotIn(".shine", source)
    test_case.assertNotIn("case .cursorRipple:", logical_body)

    capability = capability_source.read_text(encoding="utf-8")
    test_case.assertIn("Self.compileProgramFirstStages(", capability)
    stages = capability_stages_source.read_text(encoding="utf-8")
    program_first = capability_program_first_source.read_text(encoding="utf-8")
    for product_source in (stages, program_first):
        test_case.assertNotIn("yieldsToResolvedMaterialProgram", product_source)
    for empty_argument in (
        "dedicatedStagePrograms: []",
        "dedicatedStageFamilies: [:]",
        "dedicatedLeafKeys: []",
    ):
        test_case.assertNotIn(empty_argument, program_first)
    for removed_parameter in (
        "dedicatedStagePrograms:",
        "dedicatedStageFamilies:",
        "dedicatedLeafKeys:",
    ):
        test_case.assertNotIn(removed_parameter, stages)
    test_case.assertLess(
        program_first.index("let programResult = compileStages("),
        program_first.index("case let .failure(programFailure):"),
    )
    test_case.assertNotIn("externallyOwnedImageBlendProgram", program_first)
    test_case.assertNotIn("isExternallyOwnedImageBlend(", program_first)
    test_case.assertNotIn(
        "let hasDedicatedImageBlendDependencyStage = stages.contains",
        program_first,
    )
    image_blend_case = program_first.index("case .imageLayerBlend:")
    test_case.assertIn(
        "return false",
        program_first[image_blend_case:image_blend_case + 100],
    )
    visible_graph_output_case = program_first.index(
        "case .visibleImageGraphOutput:"
    )
    test_case.assertIn(
        "return false",
        program_first[
            visible_graph_output_case:visible_graph_output_case + 120
        ],
    )
    test_case.assertIn("dedicatedLeafKeys.contains(effect.key)", program_first)
    test_case.assertIn(
        "dedicatedGraphStageKeys.contains(effect.key)", program_first
    )
    test_case.assertIn("supportsUnifiedLogicalTargetStage", program_first)
    test_case.assertNotIn("dedicatedFullFrameComposeStageKeys", program_first)
    test_case.assertNotIn("supportsUnifiedFullFrameComposeStage", program_first)
    test_case.assertIn(
        "effect.input == admitted.pairPlan.baseCaptureIdentity",
        program_first,
    )
    test_case.assertIn("sourceRoute: stageSourceRoute", program_first)
    captured_route_start = program_first.index("let sourceRouteExecutable =")
    captured_route_end = program_first.index(
        "guard pairLeaf || logicalTargetStage,",
        captured_route_start,
    )
    captured_route_guard = program_first[
        captured_route_start:captured_route_end
    ]
    captured_route_compact = "".join(captured_route_guard.split())
    test_case.assertIn(
        "stageSourceRoute!=.capturedMainTargetTexture"
        "||((pairLeaf||logicalTargetStage)"
        "&&program.executionPlan.supportsUtilityCapture)",
        captured_route_compact,
    )
    test_case.assertNotIn("fullFrameComposeStage", captured_route_guard)
    test_case.assertIn(
        "dynamicTargetsExecutable,\n                      sourceRouteExecutable else",
        program_first[captured_route_end:],
    )
