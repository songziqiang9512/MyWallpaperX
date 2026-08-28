#!/usr/bin/env python3
"""Executable Pulse owner partition for exact authored numeric fallbacks."""

from __future__ import annotations

from pathlib import Path
import runpy


BASE = runpy.run_path(
    str(Path(__file__).with_name(
        "test_scene_pulse_direct_user_property_owner_admission.py"
    ))
)
_Base = BASE["ScenePulseDirectUserPropertyOwnerAdmissionTests"]

FUNCTION_MARKER = "\n@main\nenum Harness {"
RESULT_MARKER = "        let result: [String: Any] = [\n"

FALLBACK_FUNCTIONS = r'''

private func fallbackTarget(
    _ constant: Constant,
    layer: Int = layerID,
    effectIndex: Int = 0,
    passIndex: Int = 0,
    name: String? = nil
) -> SceneDynamicTarget {
    .effectConstant(
        layerID: layer,
        effectIndex: effectIndex,
        passIndex: passIndex,
        name: name ?? constant.rawValue
    )
}

private func fallbackDefinition(
    _ constant: Constant,
    target: SceneDynamicTarget? = nil,
    valueType: SceneDynamicValueType? = nil,
    authoredValue: SceneDynamicValue
) -> SceneDynamicTargetDefinition {
    .init(
        target: target ?? fallbackTarget(constant),
        valueType: valueType ?? constant.valueType,
        authoredValue: authoredValue
    )
}

private func fallbackProducer(
    _ constant: Constant,
    propertyKey: String,
    target: SceneDynamicTarget? = nil,
    valueType: SceneDynamicValueType? = nil
) -> SceneDynamicUserPropertyProducer {
    .init(
        propertyKey: propertyKey,
        target: target ?? fallbackTarget(constant),
        valueType: valueType ?? constant.valueType
    )
}

private func fallbackInput(
    contracts: [SceneShaderContract],
    bindings: [Constant: String],
    fallbackOverrides: [Constant: [Double]],
    bindingKeyOverrides: [Constant: [String]] = [:],
    producers: Set<SceneDynamicUserPropertyProducer> = [],
    definitions: [SceneDynamicTargetDefinition] = [],
    combos: [String: Int] = [:],
    maskPath: String? = nil
) -> SceneEffectStageCompileInput {
    let input = compileInput(
        contracts: contracts,
        bindings: bindings,
        fallbackOverrides: fallbackOverrides,
        bindingKeyOverrides: bindingKeyOverrides,
        producers: producers,
        combos: combos,
        maskPath: maskPath
    )
    return .init(
        stageGraph: input.stageGraph,
        authoredOrdinal: input.authoredOrdinal,
        effectKey: input.effectKey,
        definitionPath: input.definitionPath,
        inputRole: input.inputRole,
        descriptor: input.descriptor,
        shaderContracts: input.shaderContracts,
        userPropertyProducers: input.userPropertyProducers,
        propertyDefinitions: definitions,
        timelineDefinitions: input.timelineDefinitions,
        activeEffectLocalDirectBoolVisibilityTargets:
            input.activeEffectLocalDirectBoolVisibilityTargets,
        startupInactiveEffectVisibilityTargets:
            input.startupInactiveEffectVisibilityTargets,
        frameDrivenEffectVisibilityOwners:
            input.frameDrivenEffectVisibilityOwners
    )
}

private func fallbackOutcome(
    _ contracts: [SceneShaderContract],
    bindings: [Constant: String],
    fallbackOverrides: [Constant: [Double]],
    bindingKeyOverrides: [Constant: [String]] = [:],
    producers: Set<SceneDynamicUserPropertyProducer> = [],
    definitions: [SceneDynamicTargetDefinition] = [],
    combos: [String: Int] = [:],
    maskPath: String? = nil
) -> String {
    outcome(fallbackInput(
        contracts: contracts,
        bindings: bindings,
        fallbackOverrides: fallbackOverrides,
        bindingKeyOverrides: bindingKeyOverrides,
        producers: producers,
        definitions: definitions,
        combos: combos,
        maskPath: maskPath
    ))
}

private func fallbackOwnerPartitionTargetNames() -> [[String]] {
    let definitions = [
        fallbackDefinition(
            .noiseAmount,
            authoredValue: .scalar(0.25)
        ),
        fallbackDefinition(
            .tintLow,
            authoredValue: .vector3(0.2, 0.3, 0.4)
        ),
    ]
    let liveTint = fallbackTarget(.tintLow)
    let partitions = [
        SceneEffectStageAuthoredFallbackOwnerPartition.executableTargets(
            definitions: definitions,
            liveTargets: [],
            retainedDedicatedEffects: [effectKey]
        ),
        SceneEffectStageAuthoredFallbackOwnerPartition.executableTargets(
            definitions: definitions,
            liveTargets: [liveTint],
            retainedDedicatedEffects: [effectKey]
        ),
        SceneEffectStageAuthoredFallbackOwnerPartition.executableTargets(
            definitions: definitions,
            liveTargets: [],
            retainedDedicatedEffects: []
        ),
    ]
    return partitions.map { targets in
        targets.compactMap { target in
            guard case let .effectConstant(
                actualLayer,
                actualEffect,
                actualPass,
                name
            ) = target,
                actualLayer == layerID,
                actualEffect == 0,
                actualPass == 0 else { return nil }
            return name
        }.sorted()
    }
}

private func wrapperMetadataOwnerPartition(
    _ contracts: [SceneShaderContract]
) -> [String] {
    let definition = fallbackDefinition(
        .noiseAmount,
        authoredValue: .scalar(0.25)
    )
    let wrapperOutcomes = [
        ["unexpected", "user", "value"],
        ["animation", "user", "value"],
        ["script", "user", "value"],
        ["user"],
    ].map { keys in
        fallbackOutcome(
            contracts,
            bindings: [.noiseAmount: "pulseNoiseAmount"],
            fallbackOverrides: [.noiseAmount: [0.25]],
            bindingKeyOverrides: [.noiseAmount: keys],
            definitions: [definition]
        )
    }
    return wrapperOutcomes + [fallbackOutcome(
        contracts,
        bindings: [.noiseAmount: "pulseNoiseAmount"],
        fallbackOverrides: [.noiseAmount: [0.25]],
        bindingKeyOverrides: [
            .noiseAmount: ["unexpected", "user", "value"],
        ],
        producers: [fallbackProducer(
            .noiseAmount,
            propertyKey: "pulseNoiseAmount",
            valueType: .vector3
        )],
        definitions: [definition]
    )]
}

private func tintConsumerDriftDispositions(
    _ contract: SceneShaderContract
) -> [String] {
    let tintPlan = plan(
        contracts: [contract],
        bindings: [.tintLow: "pulseTint"]
    )
    let stock = prepared(contract)
    let wrongType = copy(
        stock.fragment,
        declarations: stock.fragment.activeDeclarations.map {
            $0.declaration.name == "g_TintColor1"
                ? declaration($0, type: "vec4")
                : $0
        }
    )
    let wrongRange = replacingRange(
        stock.fragment,
        name: "g_TintColor1",
        range: 0 ... 2
    )
    return [
        ownerDisposition(
            tintPlan,
            [stock, copy(stock, fragment: wrongType)]
        ),
        ownerDisposition(
            tintPlan,
            [stock, copy(stock, fragment: wrongRange)]
        ),
    ]
}
'''

FALLBACK_RESULTS = r'''            "wrapperMetadataOwnerPartition":
                wrapperMetadataOwnerPartition(contracts),
            "fallbackScalarConstants": [
                fallbackOutcome(
                    contracts,
                    bindings: [.noiseSpeed: "pulseNoiseSpeed"],
                    fallbackOverrides: [.noiseSpeed: [0.25]],
                    definitions: [fallbackDefinition(
                        .noiseSpeed, authoredValue: .scalar(0.25)
                    )]
                ),
                fallbackOutcome(
                    contracts,
                    bindings: [.noiseAmount: "pulseNoiseAmount"],
                    fallbackOverrides: [.noiseAmount: [0.25]],
                    definitions: [fallbackDefinition(
                        .noiseAmount, authoredValue: .scalar(0.25)
                    )]
                ),
                fallbackOutcome(
                    contracts,
                    bindings: [.power: "pulsePower"],
                    fallbackOverrides: [.power: [1.25]],
                    definitions: [fallbackDefinition(
                        .power, authoredValue: .scalar(1.25)
                    )]
                ),
            ],
            "fallbackVector3Constants": [
                fallbackOutcome(
                    contracts,
                    bindings: [.tintLow: "pulseTintLow"],
                    fallbackOverrides: [.tintLow: [0.2, 0.3, 0.4]],
                    definitions: [fallbackDefinition(
                        .tintLow, authoredValue: .vector3(0.2, 0.3, 0.4)
                    )]
                ),
                fallbackOutcome(
                    contracts,
                    bindings: [.tintHigh: "pulseTintHigh"],
                    fallbackOverrides: [.tintHigh: [0.6, 0.7, 0.8]],
                    definitions: [fallbackDefinition(
                        .tintHigh, authoredValue: .vector3(0.6, 0.7, 0.8)
                    )]
                ),
            ],
            "fallbackScalarVector3Combination": fallbackOutcome(
                contracts,
                bindings: [
                    .noiseAmount: "pulseNoiseAmount",
                    .tintLow: "pulseTintLow",
                ],
                fallbackOverrides: [
                    .noiseAmount: [0.25],
                    .tintLow: [0.2, 0.3, 0.4],
                ],
                definitions: [
                    fallbackDefinition(
                        .noiseAmount, authoredValue: .scalar(0.25)
                    ),
                    fallbackDefinition(
                        .tintLow, authoredValue: .vector3(0.2, 0.3, 0.4)
                    ),
                ]
            ),
            "fallbackOwnerPartitionTargetNames":
                fallbackOwnerPartitionTargetNames(),
            "missingAndDuplicateDefinitions": [
                fallbackOutcome(
                    contracts,
                    bindings: [.noiseAmount: "pulseNoise"],
                    fallbackOverrides: [.noiseAmount: [0.25]]
                ),
                fallbackOutcome(
                    contracts,
                    bindings: [.noiseAmount: "pulseNoise"],
                    fallbackOverrides: [.noiseAmount: [0.25]],
                    definitions: [
                        fallbackDefinition(
                            .noiseAmount, authoredValue: .scalar(0.25)
                        ),
                        fallbackDefinition(
                            .noiseAmount, authoredValue: .scalar(0.25)
                        ),
                    ]
                ),
            ],
            "definitionIdentityRemainders": [
                fallbackOutcome(
                    contracts,
                    bindings: [.noiseAmount: "pulseNoise"],
                    fallbackOverrides: [.noiseAmount: [0.25]],
                    definitions: [fallbackDefinition(
                        .noiseAmount,
                        target: fallbackTarget(.noiseAmount, layer: layerID + 1),
                        authoredValue: .scalar(0.25)
                    )]
                ),
                fallbackOutcome(
                    contracts,
                    bindings: [.noiseAmount: "pulseNoise"],
                    fallbackOverrides: [.noiseAmount: [0.25]],
                    definitions: [fallbackDefinition(
                        .noiseAmount,
                        target: fallbackTarget(.noiseAmount, effectIndex: 1),
                        authoredValue: .scalar(0.25)
                    )]
                ),
                fallbackOutcome(
                    contracts,
                    bindings: [.noiseAmount: "pulseNoise"],
                    fallbackOverrides: [.noiseAmount: [0.25]],
                    definitions: [fallbackDefinition(
                        .noiseAmount,
                        target: fallbackTarget(.noiseAmount, passIndex: 1),
                        authoredValue: .scalar(0.25)
                    )]
                ),
                fallbackOutcome(
                    contracts,
                    bindings: [.noiseAmount: "pulseNoise"],
                    fallbackOverrides: [.noiseAmount: [0.25]],
                    definitions: [fallbackDefinition(
                        .noiseAmount,
                        target: fallbackTarget(.noiseAmount, name: "otherNoise"),
                        authoredValue: .scalar(0.25)
                    )]
                ),
            ],
            "definitionValueRemainders": [
                fallbackOutcome(
                    contracts,
                    bindings: [.noiseAmount: "pulseNoise"],
                    fallbackOverrides: [.noiseAmount: [0.25]],
                    definitions: [fallbackDefinition(
                        .noiseAmount,
                        valueType: .vector2,
                        authoredValue: .vector2(0.25, 0.25)
                    )]
                ),
                fallbackOutcome(
                    contracts,
                    bindings: [.noiseAmount: "pulseNoise"],
                    fallbackOverrides: [.noiseAmount: [0.25]],
                    definitions: [fallbackDefinition(
                        .noiseAmount,
                        valueType: .scalar,
                        authoredValue: .vector2(0.25, 0.25)
                    )]
                ),
                fallbackOutcome(
                    contracts,
                    bindings: [.noiseAmount: "pulseNoise"],
                    fallbackOverrides: [.noiseAmount: [0.25]],
                    definitions: [fallbackDefinition(
                        .noiseAmount, authoredValue: .scalar(.nan)
                    )]
                ),
                fallbackOutcome(
                    contracts,
                    bindings: [.noiseAmount: "pulseNoise"],
                    fallbackOverrides: [.noiseAmount: [0.25]],
                    definitions: [fallbackDefinition(
                        .noiseAmount, authoredValue: .scalar(0.25000000000000006)
                    )]
                ),
                fallbackOutcome(
                    contracts,
                    bindings: [.noiseAmount: "pulseNoise"],
                    fallbackOverrides: [.noiseAmount: [-0.0]],
                    definitions: [fallbackDefinition(
                        .noiseAmount, authoredValue: .scalar(0.0)
                    )]
                ),
            ],
            "exactOutOfRangeRejections": [
                fallbackOutcome(
                    contracts,
                    bindings: [.noiseAmount: "pulseNoise"],
                    fallbackOverrides: [.noiseAmount: [2.5]],
                    definitions: [fallbackDefinition(
                        .noiseAmount, authoredValue: .scalar(2.5)
                    )]
                ),
                fallbackOutcome(
                    contracts,
                    bindings: [.tintLow: "pulseTint"],
                    fallbackOverrides: [.tintLow: [1.1, 0.3, 0.4]],
                    definitions: [fallbackDefinition(
                        .tintLow, authoredValue: .vector3(1.1, 0.3, 0.4)
                    )]
                ),
            ],
            "producerConflictRemainders": [
                fallbackOutcome(
                    contracts,
                    bindings: [.noiseAmount: "pulseNoise"],
                    fallbackOverrides: [.noiseAmount: [0.25]],
                    producers: [fallbackProducer(
                        .noiseAmount,
                        propertyKey: "wrongKey"
                    )],
                    definitions: [fallbackDefinition(
                        .noiseAmount, authoredValue: .scalar(0.25)
                    )]
                ),
                fallbackOutcome(
                    contracts,
                    bindings: [.noiseAmount: "pulseNoise"],
                    fallbackOverrides: [.noiseAmount: [0.25]],
                    producers: [fallbackProducer(
                        .noiseAmount,
                        propertyKey: "pulseNoise",
                        target: fallbackTarget(.noiseAmount, passIndex: 1)
                    )],
                    definitions: [fallbackDefinition(
                        .noiseAmount, authoredValue: .scalar(0.25)
                    )]
                ),
                fallbackOutcome(
                    contracts,
                    bindings: [.noiseAmount: "pulseNoise"],
                    fallbackOverrides: [.noiseAmount: [0.25]],
                    producers: [fallbackProducer(
                        .noiseAmount,
                        propertyKey: "pulseNoise",
                        valueType: .vector2
                    )],
                    definitions: [fallbackDefinition(
                        .noiseAmount, authoredValue: .scalar(0.25)
                    )]
                ),
                fallbackOutcome(
                    contracts,
                    bindings: [.noiseAmount: "pulseNoise"],
                    fallbackOverrides: [.noiseAmount: [0.25]],
                    producers: [
                        fallbackProducer(
                            .noiseAmount, propertyKey: "pulseNoise"
                        ),
                        fallbackProducer(
                            .noiseAmount, propertyKey: "competingNoise"
                        ),
                    ],
                    definitions: [fallbackDefinition(
                        .noiseAmount, authoredValue: .scalar(0.25)
                    )]
                ),
            ],
            "mixedSourceRemainder": fallbackOutcome(
                contracts,
                bindings: [
                    .noiseAmount: "pulseNoise",
                    .tintLow: "pulseTint",
                ],
                fallbackOverrides: [
                    .noiseAmount: [0.25],
                    .tintLow: [0.2, 0.3, 0.4],
                ],
                producers: [fallbackProducer(
                    .noiseAmount, propertyKey: "pulseNoise"
                )],
                definitions: [fallbackDefinition(
                    .tintLow, authoredValue: .vector3(0.2, 0.3, 0.4)
                )]
            ),
            "excludedConstantRemainders": [
                fallbackOutcome(
                    contracts,
                    bindings: [.speed: "pulseSpeed"],
                    fallbackOverrides: [.speed: [3]],
                    definitions: [fallbackDefinition(
                        .speed, authoredValue: .scalar(3)
                    )]
                ),
                fallbackOutcome(
                    contracts,
                    bindings: [.amount: "pulseAmount"],
                    fallbackOverrides: [.amount: [1]],
                    definitions: [fallbackDefinition(
                        .amount, authoredValue: .scalar(1)
                    )]
                ),
                fallbackOutcome(
                    contracts,
                    bindings: [.phase: "pulsePhase"],
                    fallbackOverrides: [.phase: [0.5]],
                    definitions: [fallbackDefinition(
                        .phase, authoredValue: .scalar(0.5)
                    )]
                ),
                fallbackOutcome(
                    contracts,
                    bindings: [.bounds: "pulseBounds"],
                    fallbackOverrides: [.bounds: [0.2, 0.8]],
                    definitions: [fallbackDefinition(
                        .bounds, authoredValue: .vector2(0.2, 0.8)
                    )]
                ),
            ],
            "alphaAndMaskRemainders": [
                fallbackOutcome(
                    contracts,
                    bindings: [.noiseAmount: "pulseNoise"],
                    fallbackOverrides: [.noiseAmount: [0.25]],
                    definitions: [fallbackDefinition(
                        .noiseAmount, authoredValue: .scalar(0.25)
                    )],
                    combos: ["PULSECOLOR": 1, "PULSEALPHA": 1]
                ),
                fallbackOutcome(
                    contracts,
                    bindings: [.noiseAmount: "pulseNoise"],
                    fallbackOverrides: [.noiseAmount: [0.25]],
                    definitions: [fallbackDefinition(
                        .noiseAmount, authoredValue: .scalar(0.25)
                    )],
                    maskPath: "materials/pulse-mask.png"
                ),
                fallbackOutcome(
                    contracts,
                    bindings: [.tintLow: "pulseTint"],
                    fallbackOverrides: [.tintLow: [0.2, 0.3, 0.4]],
                    definitions: [fallbackDefinition(
                        .tintLow, authoredValue: .vector3(0.2, 0.3, 0.4)
                    )],
                    combos: [
                        "AUDIOPROCESSING": 3,
                        "PULSECOLOR": 1,
                        "PULSEALPHA": 1,
                    ]
                ),
            ],
            "tintConsumerDriftDispositions":
                tintConsumerDriftDispositions(contracts[0]),
'''

base_harness = BASE["HARNESS"]
for marker, label in (
    (FUNCTION_MARKER, "function"),
    (RESULT_MARKER, "result"),
):
    if base_harness.count(marker) != 1:
        raise RuntimeError(f"Pulse fallback harness {label} marker drifted")

base_globals = _Base.setUpClass.__func__.__globals__
base_globals["HARNESS"] = base_harness.replace(
    FUNCTION_MARKER,
    FALLBACK_FUNCTIONS + FUNCTION_MARKER,
    1,
).replace(
    RESULT_MARKER,
    RESULT_MARKER + FALLBACK_RESULTS,
    1,
)


class ScenePulseAuthoredFallbackOwnerAdmissionTests(_Base):
    SCALAR_REVOKED = (
        "revoked:authored-fallback-fragment-scalar-"
        "owner-revoked-to-material-program"
    )
    VECTOR3_REVOKED = (
        "revoked:authored-fallback-fragment-vector3-"
        "owner-revoked-to-material-program"
    )
    COMBINED_REVOKED = (
        "revoked:authored-fallback-fragment-scalar-vector3-"
        "owner-revoked-to-material-program"
    )

    def test_exact_fragment_scalar_and_vector3_fallbacks_revoke_owner(
        self,
    ) -> None:
        self.assertEqual(
            self.result["fallbackScalarConstants"],
            [self.SCALAR_REVOKED] * 3,
        )
        self.assertEqual(
            self.result["fallbackVector3Constants"],
            [self.VECTOR3_REVOKED] * 2,
        )
        self.assertEqual(
            self.result["fallbackScalarVector3Combination"],
            self.COMBINED_REVOKED,
        )

    def test_retained_owner_suppresses_only_definition_only_targets(
        self,
    ) -> None:
        self.assertEqual(
            self.result["fallbackOwnerPartitionTargetNames"],
            [[], ["tintlow"], ["noiseamount", "tintlow"]],
        )

    def test_opaque_wrapper_metadata_revokes_without_bypassing_semantics(
        self,
    ) -> None:
        self.assertEqual(
            self.result["wrapperMetadataOwnerPartition"],
            [self.SCALAR_REVOKED] + ["incumbent"] * 4,
        )

    def test_missing_duplicate_or_wrong_identity_definitions_retain_owner(
        self,
    ) -> None:
        self.assertEqual(
            self.result["missingAndDuplicateDefinitions"],
            ["incumbent"] * 2,
        )
        self.assertEqual(
            self.result["definitionIdentityRemainders"],
            ["incumbent"] * 4,
        )

    def test_type_nonfinite_bit_and_signed_zero_drift_retain_owner(
        self,
    ) -> None:
        self.assertEqual(
            self.result["definitionValueRemainders"],
            ["incumbent"] * 5,
        )
        self.assertEqual(
            self.result["exactOutOfRangeRejections"],
            ["revoked:"] * 2,
        )

    def test_conflicting_and_mixed_producers_retain_owner(self) -> None:
        self.assertEqual(
            self.result["producerConflictRemainders"],
            ["incumbent"] * 4,
        )
        self.assertEqual(self.result["mixedSourceRemainder"], "incumbent")

    def test_staged_scalars_revoke_while_bounds_and_visual_remainders_stay(
        self,
    ) -> None:
        self.assertEqual(
            self.result["excludedConstantRemainders"],
            [
                "revoked:authored-fallback-profile-staged-scalar-"
                "owner-revoked-to-material-program"
            ] * 3 + ["incumbent"],
        )
        self.assertEqual(
            self.result["alphaAndMaskRemainders"],
            ["incumbent"] * 3,
        )

    def test_vector3_consumer_abi_and_domain_drift_retain_owner(self) -> None:
        self.assertEqual(
            self.result["tintConsumerDriftDispositions"],
            ["retain-incumbent"] * 2,
        )


del _Base


if __name__ == "__main__":
    import unittest

    unittest.main()
