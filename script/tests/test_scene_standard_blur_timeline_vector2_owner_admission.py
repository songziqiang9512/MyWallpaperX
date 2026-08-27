#!/usr/bin/env python3
"""Executable owner partition for Standard Blur Timeline vector2 inputs."""

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

FUNCTION_MARKER = "\n@main\nenum Harness {"
RESULT_MARKER = "        var result: [String: Any] = [\n"

TIMELINE_FUNCTIONS = r'''

private func timelineVector2(
    _ x: Double = 0.19,
    _ y: Double = 0.31,
    bindingKeys: [String] = ["animation", "value"],
    scriptSource: String? = nil
) -> SceneDocument.ShaderValue {
    .init(
        rawValue: "\(x) \(y)",
        valueKind: "binding",
        userBinding: nil,
        components: [x, y],
        timeline: .init(),
        scriptSource: scriptSource,
        bindingKeys: bindingKeys
    )
}

private func timelineDefinition(
    passIndex: Int,
    name: String = "scale",
    valueType: SceneDynamicValueType = .vector2,
    authoredValue: SceneDynamicValue = .vector2(0.19, 0.31)
) -> SceneDynamicTargetDefinition {
    .init(
        target: .effectConstant(
            layerID: layerID,
            effectIndex: 0,
            passIndex: passIndex,
            name: name
        ),
        valueType: valueType,
        authoredValue: authoredValue
    )
}

private func timelineDefinitions(
    valueType: SceneDynamicValueType = .vector2,
    authoredValue: SceneDynamicValue = .vector2(0.19, 0.31)
) -> Set<SceneDynamicTargetDefinition> {
    Set([1, 2].map {
        timelineDefinition(
            passIndex: $0,
            valueType: valueType,
            authoredValue: authoredValue
        )
    })
}

private func duplicateTimelineDefinitions()
    -> Set<SceneDynamicTargetDefinition> {
    var definitions = timelineDefinitions()
    definitions.insert(timelineDefinition(
        passIndex: 2,
        authoredValue: .vector2(0.19, 0.32)
    ))
    return definitions
}

private func timelineCompileOutcome(
    root: URL,
    horizontal: SceneDocument.ShaderValue,
    vertical: SceneDocument.ShaderValue? = nil,
    definitions: Set<SceneDynamicTargetDefinition>
) -> String {
    let input = SceneEffectStageCompileInput(
        stageGraph: graph(),
        inputRole: .layerSource,
        descriptor: descriptor(horizontal: horizontal, vertical: vertical),
        shaderContracts: contracts(root),
        timelineDefinitions: definitions
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

TIMELINE_RESULTS = r'''            "timelineOldPlanner":
                SceneAuthoredStandardBlurPlanner.plan(
                    graph: graph(),
                    descriptor: descriptor(horizontal: timelineVector2()),
                    inputRole: .layerSource
                ) != nil,
            "timelineExact": timelineCompileOutcome(
                root: stock,
                horizontal: timelineVector2(),
                definitions: timelineDefinitions()
            ),
            "timelineUnequalDefaults": [roots[2], roots[3]].map {
                timelineCompileOutcome(
                    root: $0,
                    horizontal: timelineVector2(),
                    definitions: timelineDefinitions()
                )
            },
            "timelineMissingDefaults": [roots[4], roots[5]].map {
                timelineCompileOutcome(
                    root: $0,
                    horizontal: timelineVector2(),
                    definitions: timelineDefinitions()
                )
            },
            "timelineDefinitionRemainders": [
                timelineCompileOutcome(
                    root: stock,
                    horizontal: timelineVector2(),
                    definitions: [timelineDefinition(passIndex: 1)]
                ),
                timelineCompileOutcome(
                    root: stock,
                    horizontal: timelineVector2(),
                    definitions: [
                        timelineDefinition(passIndex: 1),
                        timelineDefinition(passIndex: 2, name: "otherScale"),
                    ]
                ),
                timelineCompileOutcome(
                    root: stock,
                    horizontal: timelineVector2(),
                    definitions: duplicateTimelineDefinitions()
                ),
                timelineCompileOutcome(
                    root: stock,
                    horizontal: timelineVector2(),
                    definitions: timelineDefinitions(
                        valueType: .scalar,
                        authoredValue: .scalar(0.19)
                    )
                ),
                timelineCompileOutcome(
                    root: stock,
                    horizontal: timelineVector2(),
                    definitions: timelineDefinitions(
                        valueType: .vector3,
                        authoredValue: .vector3(0.19, 0.31, 0.5)
                    )
                ),
                timelineCompileOutcome(
                    root: stock,
                    horizontal: timelineVector2(),
                    definitions: [
                        timelineDefinition(
                            passIndex: 1,
                            authoredValue: .vector2(0.19, 0.32)
                        ),
                        timelineDefinition(passIndex: 2),
                    ]
                ),
                timelineCompileOutcome(
                    root: stock,
                    horizontal: timelineVector2(),
                    definitions: [
                        timelineDefinition(passIndex: 1),
                        timelineDefinition(
                            passIndex: 2,
                            authoredValue: .vector2(0.19, 0.32)
                        ),
                    ]
                ),
            ],
            "timelineWrapperRemainders": [
                timelineCompileOutcome(
                    root: stock,
                    horizontal: timelineVector2(),
                    vertical: vector(0.19, 0.31),
                    definitions: timelineDefinitions()
                ),
                timelineCompileOutcome(
                    root: stock,
                    horizontal: timelineVector2(
                        bindingKeys: ["animation", "extra", "value"]
                    ),
                    definitions: timelineDefinitions()
                ),
                timelineCompileOutcome(
                    root: stock,
                    horizontal: timelineVector2(
                        bindingKeys: ["animation", "script", "value"],
                        scriptSource: "return 0.19;"
                    ),
                    definitions: timelineDefinitions()
                ),
            ],
            "timelineABIRemainders": [roots[6], roots[7], roots[8], roots[9]].map {
                timelineCompileOutcome(
                    root: $0,
                    horizontal: timelineVector2(),
                    definitions: timelineDefinitions()
                )
            },
'''

base_harness = BASE["HARNESS"]
if base_harness.count(FUNCTION_MARKER) != 1:
    raise RuntimeError("Standard Blur owner harness function marker drifted")
if base_harness.count(RESULT_MARKER) != 1:
    raise RuntimeError("Standard Blur owner harness result marker drifted")
_Base.setUpClass.__func__.__globals__["HARNESS"] = base_harness.replace(
    FUNCTION_MARKER,
    TIMELINE_FUNCTIONS + FUNCTION_MARKER,
    1,
).replace(
    RESULT_MARKER,
    RESULT_MARKER + TIMELINE_RESULTS,
    1,
)


class SceneStandardBlurTimelineVector2OwnerAdmissionTests(_Base):
    REVOKED = (
        "rejected:dedicated-profile-rejected:"
        "timeline-vector2-owner-revoked-to-material-program"
    )

    def test_exact_unequal_timeline_vector2_revokes_the_old_owner(self) -> None:
        self.assertTrue(self.result["timelineOldPlanner"])
        self.assertEqual(self.result["timelineExact"], self.REVOKED)
        self.assertEqual(self.result["timelineUnequalDefaults"], [self.REVOKED] * 2)
        self.assertEqual(self.result["timelineMissingDefaults"], [self.REVOKED] * 2)

    def test_definition_remainders_retain_the_old_owner(self) -> None:
        self.assertEqual(self.result["timelineDefinitionRemainders"], ["accepted"] * 7)

    def test_wrapper_and_float2_abi_remainders_retain_the_old_owner(self) -> None:
        self.assertEqual(self.result["timelineWrapperRemainders"], ["accepted"] * 3)
        self.assertEqual(self.result["timelineABIRemainders"], ["accepted"] * 4)


del _Base


if __name__ == "__main__":
    import unittest

    unittest.main()
