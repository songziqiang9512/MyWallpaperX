#!/usr/bin/env python3
"""Executable owner partition for Standard Blur authored scalar fallbacks."""

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

FUNCTION_MARKER = "\n@main\nenum Harness {"
RESULT_MARKER = "        var result: [String: Any] = [\n"

FALLBACK_FUNCTIONS = r'''

private func fallbackUserScalar(
    _ components: [Double],
    bindingKeys: [String] = ["user", "value"]
) -> SceneDocument.ShaderValue {
    SceneDocument.ShaderValue(
        rawValue: components.map { String($0) }.joined(separator: " "),
        valueKind: "binding",
        userBinding: "blurScale",
        userValueKind: .string,
        components: components,
        bindingKeys: bindingKeys
    )
}

private func fallbackTarget(
    layer: Int = layerID,
    effectIndex: Int = 0,
    passIndex: Int,
    name: String = "scale"
) -> SceneDynamicTarget {
    .effectConstant(
        layerID: layer,
        effectIndex: effectIndex,
        passIndex: passIndex,
        name: name
    )
}

private func fallbackDefinition(
    passIndex: Int,
    target: SceneDynamicTarget? = nil,
    valueType: SceneDynamicValueType = .scalar,
    authoredValue: SceneDynamicValue = .scalar(0.19)
) -> SceneDynamicTargetDefinition {
    .init(
        target: target ?? fallbackTarget(passIndex: passIndex),
        valueType: valueType,
        authoredValue: authoredValue
    )
}

private func fallbackDefinitions(
    horizontal: SceneDynamicValue = .scalar(0.19),
    vertical: SceneDynamicValue = .scalar(0.19)
) -> [SceneDynamicTargetDefinition] {
    [
        fallbackDefinition(passIndex: 1, authoredValue: horizontal),
        fallbackDefinition(passIndex: 2, authoredValue: vertical),
    ]
}

private func fallbackProducer(
    passIndex: Int,
    propertyKey: String = "blurScale",
    valueType: SceneDynamicValueType = .scalar
) -> SceneDynamicUserPropertyProducer {
    .init(
        propertyKey: propertyKey,
        target: fallbackTarget(passIndex: passIndex),
        valueType: valueType
    )
}

private func fallbackCompileOutcome(
    root: URL,
    horizontal: SceneDocument.ShaderValue,
    vertical: SceneDocument.ShaderValue? = nil,
    producers: Set<SceneDynamicUserPropertyProducer> = [],
    definitions: [SceneDynamicTargetDefinition] = []
) -> String {
    let input = SceneEffectStageCompileInput(
        stageGraph: graph(),
        inputRole: .layerSource,
        descriptor: descriptor(horizontal: horizontal, vertical: vertical),
        shaderContracts: contracts(root),
        userPropertyProducers: producers,
        propertyDefinitions: definitions
    )
    switch SceneAuthoredStandardBlurPlanner.compile(input) {
    case .notApplicable: return "not-applicable"
    case .accepted: return "accepted"
    case let .rejected(failure):
        return ["rejected", failure.code.rawValue, failure.details.first ?? ""]
            .joined(separator: ":")
    }
}

private func executableFallbackTargetCount(
    retainedEffects: Set<Graph.EffectKey>,
    liveTargets: Set<SceneDynamicTarget> = []
) -> Int {
    SceneEffectStageAuthoredFallbackOwnerPartition.executableTargets(
        definitions: fallbackDefinitions(),
        liveTargets: liveTargets,
        retainedDedicatedEffects: retainedEffects
    ).count
}
'''

FALLBACK_RESULTS = r'''            "fallbackEqualPair": fallbackCompileOutcome(
                root: stock,
                horizontal: fallbackUserScalar([0.19, 0.19]),
                definitions: fallbackDefinitions()
            ),
            "fallbackSingleScalar": fallbackCompileOutcome(
                root: stock,
                horizontal: fallbackUserScalar([0.19]),
                definitions: fallbackDefinitions()
            ),
            "opaqueWrapperMetadata": fallbackCompileOutcome(
                root: stock,
                horizontal: fallbackUserScalar(
                    [0.19],
                    bindingKeys: ["unexpected", "user", "value"]
                ),
                definitions: fallbackDefinitions()
            ),
            "semanticWrapperMetadata": [
                "animation", "script", "scriptproperties"
            ].map { key in
                fallbackCompileOutcome(
                    root: stock,
                    horizontal: fallbackUserScalar(
                        [0.19],
                        bindingKeys: [key, "user", "value"]
                    ),
                    definitions: fallbackDefinitions()
                )
            },
            "duplicateWrapperKey": fallbackCompileOutcome(
                root: stock,
                horizontal: fallbackUserScalar(
                    [0.19],
                    bindingKeys: ["user", "value", "value"]
                ),
                definitions: fallbackDefinitions()
            ),
            "signedZeroPairRejected": fallbackCompileOutcome(
                root: stock,
                horizontal: fallbackUserScalar([-0.0, 0.0]),
                definitions: fallbackDefinitions(
                    horizontal: .scalar(-0.0),
                    vertical: .scalar(-0.0)
                )
            ),
            "existingLiveProducer": fallbackCompileOutcome(
                root: stock,
                horizontal: fallbackUserScalar([0.19, 0.19]),
                producers: producers()
            ),
            "fallbackOwnerPartition": [
                executableFallbackTargetCount(retainedEffects: [effectKey]),
                executableFallbackTargetCount(
                    retainedEffects: [effectKey],
                    liveTargets: Set([1, 2].map {
                        fallbackTarget(passIndex: $0)
                    })
                ),
                executableFallbackTargetCount(retainedEffects: []),
                executableFallbackTargetCount(retainedEffects: [.init(
                    layerID: layerID + 1,
                    effectIndex: 0,
                    descriptorID: "foreign#effect#0"
                )]),
            ],
            "missingDefinitionRemainders": [
                fallbackCompileOutcome(
                    root: stock,
                    horizontal: fallbackUserScalar([0.19, 0.19])
                ),
                fallbackCompileOutcome(
                    root: stock,
                    horizontal: fallbackUserScalar([0.19, 0.19]),
                    definitions: [fallbackDefinition(passIndex: 1)]
                ),
                fallbackCompileOutcome(
                    root: stock,
                    horizontal: fallbackUserScalar([0.19, 0.19]),
                    definitions: [fallbackDefinition(passIndex: 2)]
                ),
            ],
            "definitionIdentityRemainders": [
                fallbackCompileOutcome(
                    root: stock,
                    horizontal: fallbackUserScalar([0.19, 0.19]),
                    definitions: [
                        fallbackDefinition(
                            passIndex: 1,
                            target: .effectVisibility(
                                layerID: layerID,
                                effectIndex: 0
                            )
                        ),
                        fallbackDefinition(passIndex: 2),
                    ]
                ),
                fallbackCompileOutcome(
                    root: stock,
                    horizontal: fallbackUserScalar([0.19, 0.19]),
                    definitions: [
                        fallbackDefinition(
                            passIndex: 1,
                            target: fallbackTarget(
                                passIndex: 1,
                                name: "otherScale"
                            )
                        ),
                        fallbackDefinition(passIndex: 2),
                    ]
                ),
                fallbackCompileOutcome(
                    root: stock,
                    horizontal: fallbackUserScalar([0.19, 0.19]),
                    definitions: [
                        fallbackDefinition(
                            passIndex: 1,
                            target: fallbackTarget(passIndex: 3)
                        ),
                        fallbackDefinition(passIndex: 2),
                    ]
                ),
                fallbackCompileOutcome(
                    root: stock,
                    horizontal: fallbackUserScalar([0.19, 0.19]),
                    definitions: [
                        fallbackDefinition(
                            passIndex: 1,
                            target: fallbackTarget(
                                layer: layerID + 1,
                                passIndex: 1
                            )
                        ),
                        fallbackDefinition(passIndex: 2),
                    ]
                ),
                fallbackCompileOutcome(
                    root: stock,
                    horizontal: fallbackUserScalar([0.19, 0.19]),
                    definitions: [
                        fallbackDefinition(
                            passIndex: 1,
                            target: fallbackTarget(
                                effectIndex: 1,
                                passIndex: 1
                            )
                        ),
                        fallbackDefinition(passIndex: 2),
                    ]
                ),
            ],
            "definitionTypeRemainders": [
                fallbackCompileOutcome(
                    root: stock,
                    horizontal: fallbackUserScalar([0.19, 0.19]),
                    definitions: [
                        fallbackDefinition(
                            passIndex: 1,
                            valueType: .vector2,
                            authoredValue: .vector2(0.19, 0.19)
                        ),
                        fallbackDefinition(passIndex: 2),
                    ]
                ),
                fallbackCompileOutcome(
                    root: stock,
                    horizontal: fallbackUserScalar([0.19, 0.19]),
                    definitions: [
                        fallbackDefinition(
                            passIndex: 1,
                            valueType: .scalar,
                            authoredValue: .vector2(0.19, 0.19)
                        ),
                        fallbackDefinition(passIndex: 2),
                    ]
                ),
                fallbackCompileOutcome(
                    root: stock,
                    horizontal: fallbackUserScalar([0.19, 0.19]),
                    definitions: [
                        fallbackDefinition(
                            passIndex: 1,
                            valueType: .vector2,
                            authoredValue: .scalar(0.19)
                        ),
                        fallbackDefinition(passIndex: 2),
                    ]
                ),
            ],
            "duplicateDefinitionRemainders": [
                fallbackCompileOutcome(
                    root: stock,
                    horizontal: fallbackUserScalar([0.19, 0.19]),
                    definitions: fallbackDefinitions() + [
                        fallbackDefinition(passIndex: 1)
                    ]
                ),
                fallbackCompileOutcome(
                    root: stock,
                    horizontal: fallbackUserScalar([0.19, 0.19]),
                    definitions: fallbackDefinitions() + [
                        fallbackDefinition(
                            passIndex: 1,
                            authoredValue: .scalar(0.31)
                        )
                    ]
                ),
            ],
            "nonfiniteDefinitionRemainders": [
                fallbackCompileOutcome(
                    root: stock,
                    horizontal: fallbackUserScalar([0.19, 0.19]),
                    definitions: fallbackDefinitions(
                        horizontal: .scalar(.nan)
                    )
                ),
                fallbackCompileOutcome(
                    root: stock,
                    horizontal: fallbackUserScalar([0.19, 0.19]),
                    definitions: fallbackDefinitions(
                        vertical: .scalar(.infinity)
                    )
                ),
            ],
            "bitMismatchRemainders": [
                fallbackCompileOutcome(
                    root: stock,
                    horizontal: fallbackUserScalar([0.19, 0.19]),
                    definitions: fallbackDefinitions(
                        horizontal: .scalar(0.31)
                    )
                ),
                fallbackCompileOutcome(
                    root: stock,
                    horizontal: fallbackUserScalar([0.19, 0.19]),
                    definitions: fallbackDefinitions(
                        vertical: .scalar(0.31)
                    )
                ),
            ],
            "mixedOwnerRemainders": [
                fallbackCompileOutcome(
                    root: stock,
                    horizontal: fallbackUserScalar([0.19, 0.19]),
                    producers: [fallbackProducer(passIndex: 1)],
                    definitions: [fallbackDefinition(passIndex: 2)]
                ),
                fallbackCompileOutcome(
                    root: stock,
                    horizontal: fallbackUserScalar([0.19, 0.19]),
                    producers: [fallbackProducer(passIndex: 2)],
                    definitions: [fallbackDefinition(passIndex: 1)]
                ),
            ],
            "producerRemainders": [
                fallbackCompileOutcome(
                    root: stock,
                    horizontal: fallbackUserScalar([0.19, 0.19]),
                    producers: [fallbackProducer(passIndex: 3)],
                    definitions: fallbackDefinitions()
                ),
                fallbackCompileOutcome(
                    root: stock,
                    horizontal: fallbackUserScalar([0.19, 0.19]),
                    producers: [
                        fallbackProducer(
                            passIndex: 1,
                            propertyKey: "otherBlurScale"
                        ),
                        fallbackProducer(passIndex: 2),
                    ],
                    definitions: fallbackDefinitions()
                ),
                fallbackCompileOutcome(
                    root: stock,
                    horizontal: fallbackUserScalar([0.19, 0.19]),
                    producers: [
                        fallbackProducer(passIndex: 1, valueType: .vector2),
                        fallbackProducer(passIndex: 2),
                    ],
                    definitions: fallbackDefinitions()
                ),
                fallbackCompileOutcome(
                    root: stock,
                    horizontal: fallbackUserScalar([0.19, 0.19]),
                    producers: [
                        fallbackProducer(passIndex: 1),
                        fallbackProducer(
                            passIndex: 1,
                            propertyKey: "otherBlurScale"
                        ),
                        fallbackProducer(passIndex: 2),
                    ],
                    definitions: fallbackDefinitions()
                ),
            ],
'''

base_harness = BASE["HARNESS"]
for marker, label in (
    (FUNCTION_MARKER, "function"),
    (RESULT_MARKER, "result"),
):
    if base_harness.count(marker) != 1:
        raise RuntimeError(f"Standard Blur owner harness {label} marker drifted")

base_globals = _Base.setUpClass.__func__.__globals__
base_globals["SWIFT_SOURCES"] = BASE["unique_sources"]([
    *BASE["SWIFT_SOURCES"],
    SCENE_ROOT
    / "RenderGraph/EffectCompilation/SceneEffectStageAuthoredFallbackOwnerPartition.swift",
    SCENE_ROOT
    / "RenderGraph/EffectCompilation/SceneEffectStageStandardBlurScalarOwnerAdmission.swift",
])
base_globals["HARNESS"] = base_harness.replace(
    FUNCTION_MARKER,
    FALLBACK_FUNCTIONS + FUNCTION_MARKER,
    1,
).replace(
    RESULT_MARKER,
    RESULT_MARKER + FALLBACK_RESULTS,
    1,
)


class SceneStandardBlurAuthoredFallbackOwnerAdmissionTests(_Base):
    FALLBACK_REVOKED = (
        "rejected:dedicated-profile-rejected:"
        "authored-fallback-scalar-splat-owner-revoked-to-material-program"
    )
    LIVE_REVOKED = (
        "rejected:dedicated-profile-rejected:"
        "typed-user-scalar-splat-owner-revoked-to-material-program"
    )

    def test_scalar_and_equal_pair_fallbacks_revoke_the_incumbent(self) -> None:
        self.assertEqual(self.result["fallbackEqualPair"], self.FALLBACK_REVOKED)
        self.assertEqual(self.result["fallbackSingleScalar"], self.FALLBACK_REVOKED)
        self.assertEqual(
            self.result["signedZeroPairRejected"],
            "rejected:dedicated-profile-rejected:",
        )

    def test_opaque_wrapper_metadata_uses_the_shared_direct_user_contract(
        self,
    ) -> None:
        self.assertEqual(self.result["opaqueWrapperMetadata"], self.FALLBACK_REVOKED)
        self.assertEqual(self.result["semanticWrapperMetadata"], ["accepted"] * 3)
        self.assertEqual(self.result["duplicateWrapperKey"], "accepted")

    def test_existing_sole_live_producer_reason_is_unchanged(self) -> None:
        self.assertEqual(self.result["existingLiveProducer"], self.LIVE_REVOKED)

    def test_retained_dedicated_owner_blocks_only_definition_only_targets(
        self,
    ) -> None:
        self.assertEqual(self.result["fallbackOwnerPartition"], [0, 2, 2, 2])

    def test_missing_or_wrong_identity_definitions_retain_the_incumbent(
        self,
    ) -> None:
        self.assertEqual(
            self.result["missingDefinitionRemainders"],
            ["accepted"] * 3,
        )
        self.assertEqual(
            self.result["definitionIdentityRemainders"],
            ["accepted"] * 5,
        )

    def test_invalid_typed_or_duplicated_definitions_retain_the_incumbent(
        self,
    ) -> None:
        self.assertEqual(
            self.result["definitionTypeRemainders"],
            ["accepted"] * 3,
        )
        self.assertEqual(
            self.result["duplicateDefinitionRemainders"],
            ["accepted"] * 2,
        )

    def test_nonfinite_and_bit_mismatched_values_retain_the_incumbent(
        self,
    ) -> None:
        self.assertEqual(
            self.result["nonfiniteDefinitionRemainders"],
            ["accepted"] * 2,
        )
        self.assertEqual(
            self.result["bitMismatchRemainders"],
            ["accepted"] * 2,
        )

    def test_mixed_wrong_and_multiple_producers_retain_the_incumbent(
        self,
    ) -> None:
        self.assertEqual(
            self.result["mixedOwnerRemainders"],
            ["accepted"] * 2,
        )
        self.assertEqual(
            self.result["producerRemainders"],
            ["accepted"] * 4,
        )


del _Base


if __name__ == "__main__":
    import unittest

    unittest.main()
