#!/usr/bin/env python3
"""Executable owner partition for startup-false Standard Blur visibility."""

from __future__ import annotations

from pathlib import Path
import runpy


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
BASE = runpy.run_path(
    str(
        REPOSITORY_ROOT
        / "script/tests/test_scene_standard_blur_static_scalar_owner_admission.py"
    )
)
_Base = BASE["SceneStandardBlurStaticScalarOwnerAdmissionTests"]
SCENE_ROOT = BASE["SCENE_ROOT"]
LAUNCH_SOURCE = SCENE_ROOT / "Runtime/SceneDesktopWallpaperHost+Launch.swift"
DEDICATED_STAGES_SOURCE = SCENE_ROOT / (
    "RenderGraph/EffectCompilation/SceneEffectProgramCompiler+DedicatedStages.swift"
)

FUNCTION_MARKER = "\n@main\nenum Harness {"
RESULT_MARKER = "        var result: [String: Any] = [\n"
DESCRIPTOR_MARKER = r'''private func descriptor(
    horizontal: SceneDocument.ShaderValue,
    vertical: SceneDocument.ShaderValue? = nil
) -> SceneRenderDescriptor {'''
DESCRIPTOR_WITH_VISIBILITY = r'''private func descriptor(
    horizontal: SceneDocument.ShaderValue,
    vertical: SceneDocument.ShaderValue? = nil,
    effectVisible: Bool = true
) -> SceneRenderDescriptor {'''
VISIBLE_MARKER = "                visible: true,\n"

STARTUP_FUNCTIONS = r'''

private func visibilityTarget(
    effectIndex: Int = 0
) -> SceneDynamicTarget {
    .effectVisibility(layerID: layerID, effectIndex: effectIndex)
}

private func visibilityProducer(
    propertyKey: String = "blurVisible",
    effectIndex: Int = 0,
    valueType: SceneDynamicValueType = .bool
) -> SceneDynamicUserPropertyProducer {
    .init(
        propertyKey: propertyKey,
        target: visibilityTarget(effectIndex: effectIndex),
        valueType: valueType
    )
}

private func startupVisibilityCompileOutcome(
    root: URL,
    effectVisible: Bool,
    producers: Set<SceneDynamicUserPropertyProducer>,
    activeTargets: Set<SceneDynamicTarget> = [],
    startupTargets: Set<SceneDynamicTarget> = [],
    frameDrivenOwners:
        Set<SceneEffectStageCompileInput.DynamicEffectVisibilityOwner> = []
) -> String {
    let input = SceneEffectStageCompileInput(
        stageGraph: graph(),
        inputRole: .layerSource,
        descriptor: descriptor(
            horizontal: scalar(kind: "string"),
            effectVisible: effectVisible
        ),
        shaderContracts: contracts(root),
        userPropertyProducers: producers,
        activeEffectLocalDirectBoolVisibilityTargets: activeTargets,
        startupInactiveEffectVisibilityTargets: startupTargets,
        frameDrivenEffectVisibilityOwners: frameDrivenOwners
    )
    switch SceneAuthoredStandardBlurPlanner.compile(input) {
    case .notApplicable: return "not-applicable"
    case .accepted: return "accepted"
    case let .rejected(failure):
        return ["rejected", failure.code.rawValue, failure.details.first ?? ""]
            .joined(separator: ":")
    }
}
'''

STARTUP_RESULTS = r'''            "startupFalseOldPlanner":
                SceneAuthoredStandardBlurPlanner.plan(
                    graph: graph(),
                    descriptor: descriptor(
                        horizontal: scalar(kind: "string"),
                        effectVisible: false
                    ),
                    inputRole: .layerSource
                ) != nil,
            "startupFalseExact": startupVisibilityCompileOutcome(
                root: stock,
                effectVisible: false,
                producers: [visibilityProducer()],
                startupTargets: [visibilityTarget()]
            ),
            "startupFalseMissingSet": startupVisibilityCompileOutcome(
                root: stock,
                effectVisible: false,
                producers: [visibilityProducer()]
            ),
            "startupFalseActiveSetOnly": startupVisibilityCompileOutcome(
                root: stock,
                effectVisible: false,
                producers: [visibilityProducer()],
                activeTargets: [visibilityTarget()]
            ),
            "startupFalseWrongSetTarget": startupVisibilityCompileOutcome(
                root: stock,
                effectVisible: false,
                producers: [visibilityProducer()],
                startupTargets: [visibilityTarget(effectIndex: 1)]
            ),
            "startupFalseProducerRemainders": [
                startupVisibilityCompileOutcome(
                    root: stock,
                    effectVisible: false,
                    producers: [],
                    startupTargets: [visibilityTarget()]
                ),
                startupVisibilityCompileOutcome(
                    root: stock,
                    effectVisible: false,
                    producers: [visibilityProducer(valueType: .scalar)],
                    startupTargets: [visibilityTarget()]
                ),
                startupVisibilityCompileOutcome(
                    root: stock,
                    effectVisible: false,
                    producers: [visibilityProducer(effectIndex: 1)],
                    startupTargets: [visibilityTarget()]
                ),
                startupVisibilityCompileOutcome(
                    root: stock,
                    effectVisible: false,
                    producers: [
                        visibilityProducer(propertyKey: "blurVisibleA"),
                        visibilityProducer(propertyKey: "blurVisibleB"),
                    ],
                    startupTargets: [visibilityTarget()]
                ),
            ],
            "startupFalseFrameDrivenRemainders": [
                startupVisibilityCompileOutcome(
                    root: stock,
                    effectVisible: false,
                    producers: [visibilityProducer()],
                    startupTargets: [visibilityTarget()],
                    frameDrivenOwners: [
                        .init(layerID: layerID, effectIndex: 0),
                    ]
                ),
                startupVisibilityCompileOutcome(
                    root: stock,
                    effectVisible: false,
                    producers: [visibilityProducer()],
                    startupTargets: [visibilityTarget()],
                    frameDrivenOwners: [
                        .init(layerID: layerID, effectIndex: 1),
                    ]
                ),
            ],
            "activeDirectBool": startupVisibilityCompileOutcome(
                root: stock,
                effectVisible: true,
                producers: [visibilityProducer()],
                activeTargets: [visibilityTarget()]
            ),
'''

base_harness = BASE["HARNESS"]
for marker, label in (
    (FUNCTION_MARKER, "function"),
    (RESULT_MARKER, "result"),
    (DESCRIPTOR_MARKER, "descriptor"),
    (VISIBLE_MARKER, "visibility"),
):
    if base_harness.count(marker) != 1:
        raise RuntimeError(f"Standard Blur owner harness {label} marker drifted")

base_harness = base_harness.replace(
    DESCRIPTOR_MARKER,
    DESCRIPTOR_WITH_VISIBILITY,
    1,
).replace(
    VISIBLE_MARKER,
    "                visible: effectVisible,\n",
    1,
)
_Base.setUpClass.__func__.__globals__["HARNESS"] = base_harness.replace(
    FUNCTION_MARKER,
    STARTUP_FUNCTIONS + FUNCTION_MARKER,
    1,
).replace(
    RESULT_MARKER,
    RESULT_MARKER + STARTUP_RESULTS,
    1,
)


class SceneStandardBlurStartupFalseDirectBoolOwnerAdmissionTests(_Base):
    STARTUP_REVOKED = (
        "rejected:dedicated-profile-rejected:"
        "startup-inactive-direct-bool-"
        "static-scalar-owner-revoked-to-material-program"
    )
    ACTIVE_REVOKED = (
        "rejected:dedicated-profile-rejected:"
        "static-scalar-owner-revoked-to-material-program"
    )

    def test_exact_startup_false_direct_bool_revokes_the_incumbent(self) -> None:
        self.assertTrue(self.result["startupFalseOldPlanner"])
        self.assertEqual(self.result["startupFalseExact"], self.STARTUP_REVOKED)

    def test_startup_membership_is_exact_and_fail_closed(self) -> None:
        self.assertEqual(self.result["startupFalseMissingSet"], "accepted")
        self.assertEqual(self.result["startupFalseActiveSetOnly"], "accepted")
        self.assertEqual(self.result["startupFalseWrongSetTarget"], "accepted")

    def test_unproven_startup_producers_retain_the_incumbent(self) -> None:
        self.assertEqual(
            self.result["startupFalseProducerRemainders"],
            ["accepted"] * 4,
        )

    def test_frame_driven_owner_on_same_layer_retains_the_incumbent(self) -> None:
        self.assertEqual(
            self.result["startupFalseFrameDrivenRemainders"],
            ["accepted", "accepted"],
        )

    def test_active_direct_bool_owner_gate_is_unchanged(self) -> None:
        self.assertEqual(self.result["activeDirectBool"], self.ACTIVE_REVOKED)

    def test_launch_and_dedicated_compiler_forward_startup_targets(self) -> None:
        launch = "".join(LAUNCH_SOURCE.read_text(encoding="utf-8").split())
        launch_call = launch[
            launch.index("letdedicatedStageLeaves=") :
            launch.index("letdedicatedStageFamilies=")
        ]
        self.assertEqual(
            launch_call.count(
                "startupInactiveEffectVisibilityTargets:"
                "runtimeInput.startupInactiveEffectVisibilityTargets"
            ),
            1,
        )

        dedicated = "".join(
            DEDICATED_STAGES_SOURCE.read_text(encoding="utf-8").split()
        )
        compile_function = dedicated[
            dedicated.index("nonisolatedstaticfunccompileDedicatedLeaves(") :
            dedicated.index("nonisolatedstaticfuncresolveDedicatedStage(")
        ]
        self.assertEqual(
            compile_function.count(
                "startupInactiveEffectVisibilityTargets:"
                "Set<SceneDynamicTarget>=[]"
            ),
            1,
        )
        stage_input = compile_function[
            compile_function.index("letinput=SceneEffectStageCompileInput(") :
            compile_function.index("guardcaselet.accepted(backend,plan,probes)=")
        ]
        self.assertEqual(
            stage_input.count(
                "startupInactiveEffectVisibilityTargets:"
                "startupInactiveEffectVisibilityTargets"
            ),
            1,
        )


del _Base


if __name__ == "__main__":
    import unittest

    unittest.main()
