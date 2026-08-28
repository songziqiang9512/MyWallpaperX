#!/usr/bin/env python3
"""Executable X-Ray owner partition for authored scalar fallbacks."""

from __future__ import annotations

from pathlib import Path
import runpy


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
BASE = runpy.run_path(
    str(Path(__file__).with_name("test_scene_xray_scalar_owner_admission.py"))
)
_Base = BASE["SceneXRayScalarOwnerAdmissionTests"]

FUNCTION_MARKER = "\n@main\nenum Harness {"
RESULT_MARKER = "        let result: [String: Any] = [\n"

FALLBACK_FUNCTIONS = r'''

private func fallbackTarget(
    layer: Int = layerID,
    effectIndex: Int = 0,
    passIndex: Int = 0,
    name: String
) -> SceneDynamicTarget {
    .effectConstant(
        layerID: layer,
        effectIndex: effectIndex,
        passIndex: passIndex,
        name: name
    )
}

private func fallbackDefinition(
    name: String,
    target: SceneDynamicTarget? = nil,
    valueType: SceneDynamicValueType = .scalar,
    authoredValue: SceneDynamicValue
) -> SceneDynamicTargetDefinition {
    .init(
        target: target ?? fallbackTarget(name: name),
        valueType: valueType,
        authoredValue: authoredValue
    )
}

private func fallbackProducer(
    _ propertyKey: String,
    name: String,
    layer: Int = layerID,
    effectIndex: Int = 0,
    passIndex: Int = 0,
    type: SceneDynamicValueType = .scalar
) -> SceneDynamicUserPropertyProducer {
    .init(
        propertyKey: propertyKey,
        target: fallbackTarget(
            layer: layer,
            effectIndex: effectIndex,
            passIndex: passIndex,
            name: name
        ),
        valueType: type
    )
}

private func fallbackDescriptor(
    effectVisible: Bool? = true,
    sizeFallback: Double = 0.25,
    multiplyFallback: Double = 1.5,
    sizeProperty: String? = nil,
    multiplyProperty: String? = nil,
    extraSizeBindingKey: Bool = false,
    sizeScript: String? = nil
) -> SceneRenderDescriptor {
    let values = [
        "size": value(
            sizeFallback,
            propertyKey: sizeProperty,
            extraBindingKey: extraSizeBindingKey,
            script: sizeScript
        ),
        "multiply": value(
            multiplyFallback,
            propertyKey: multiplyProperty
        ),
    ]
    let pass = SceneRenderDescriptor.EffectDescriptor.PassDescriptor(
        passIndex: 0,
        texturePaths: ["textures/blend.jpg", "particle/halo_6"],
        textureSlots: [nil, "textures/blend.jpg", "particle/halo_6"],
        userTextureInputs: [],
        combos: ["BLENDMODE": 0],
        constantShaderValues: values
    )
    return .init(
        layers: [.init(
            id: layerID,
            contentKind: "image",
            effects: [.init(
                id: effectKey.descriptorID,
                file: "effects/xray/effect.json",
                visible: effectVisible,
                passes: [pass]
            )]
        )],
        materialPasses: [.init(
            id: "materials/effects/xray.json#0",
            materialPath: "materials/effects/xray.json",
            passIndex: 0,
            shaderPath: "effects/xray",
            texturePaths: [],
            textureSlots: [],
            userTextureInputs: [],
            combos: [:],
            constantShaderValues: [:],
            userShaderValues: [:],
            blending: "normal",
            depthTest: "disabled",
            depthWrite: "disabled",
            cullMode: "nocull",
            alphaWriting: nil
        )]
    )
}

private func fallbackCompileInput(
    root: URL,
    effectVisible: Bool? = true,
    sizeFallback: Double = 0.25,
    multiplyFallback: Double = 1.5,
    sizeProperty: String? = nil,
    multiplyProperty: String? = nil,
    producers: Set<SceneDynamicUserPropertyProducer> = [],
    definitions: [SceneDynamicTargetDefinition] = [],
    startupTargets: Set<SceneDynamicTarget> = [],
    extraSizeBindingKey: Bool = false,
    sizeScript: String? = nil
) -> SceneEffectStageCompileInput {
    .init(
        stageGraph: graph(),
        effectKey: effectKey,
        definitionPath: "effects/xray/effect.json",
        inputRole: .layerSource,
        descriptor: fallbackDescriptor(
            effectVisible: effectVisible,
            sizeFallback: sizeFallback,
            multiplyFallback: multiplyFallback,
            sizeProperty: sizeProperty,
            multiplyProperty: multiplyProperty,
            extraSizeBindingKey: extraSizeBindingKey,
            sizeScript: sizeScript
        ),
        shaderContracts: [contract(root)],
        userPropertyProducers: producers,
        propertyDefinitions: definitions,
        startupInactiveEffectVisibilityTargets: startupTargets
    )
}

private func fallbackOutcome(
    root: URL,
    effectVisible: Bool? = true,
    sizeFallback: Double = 0.25,
    multiplyFallback: Double = 1.5,
    sizeProperty: String? = nil,
    multiplyProperty: String? = nil,
    producers: Set<SceneDynamicUserPropertyProducer> = [],
    definitions: [SceneDynamicTargetDefinition] = [],
    startupTargets: Set<SceneDynamicTarget> = [],
    extraSizeBindingKey: Bool = false,
    sizeScript: String? = nil
) -> String {
    let product = productCompilerResult(fallbackCompileInput(
        root: root,
        effectVisible: effectVisible,
        sizeFallback: sizeFallback,
        multiplyFallback: multiplyFallback,
        sizeProperty: sizeProperty,
        multiplyProperty: multiplyProperty,
        producers: producers,
        definitions: definitions,
        startupTargets: startupTargets,
        extraSizeBindingKey: extraSizeBindingKey,
        sizeScript: sizeScript
    ))
    return product.detail.isEmpty
        ? product.outcome
        : "\(product.outcome):\(product.detail)"
}

private func ownerPartitionTargetNames() -> [[String]] {
    let definitions = [
        fallbackDefinition(name: "size", authoredValue: .scalar(0.25)),
        fallbackDefinition(name: "multiply", authoredValue: .scalar(1.5)),
    ]
    let liveMultiply = fallbackTarget(name: "multiply")
    let partitions = [
        SceneEffectStageAuthoredFallbackOwnerPartition.executableTargets(
            definitions: definitions,
            liveTargets: [],
            retainedDedicatedEffects: [effectKey]
        ),
        SceneEffectStageAuthoredFallbackOwnerPartition.executableTargets(
            definitions: definitions,
            liveTargets: [liveMultiply],
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
                layerID,
                effectIndex,
                passIndex,
                name
            ) = target,
                layerID == 42,
                effectIndex == 0,
                passIndex == 0 else { return nil }
            return name
        }.sorted()
    }
}
'''

FALLBACK_RESULTS = r'''            "sizeFallbackMultiplyStatic": fallbackOutcome(
                root: stock,
                sizeProperty: "xraySize",
                definitions: [fallbackDefinition(
                    name: "size", authoredValue: .scalar(0.25)
                )]
            ),
            "sizeStaticMultiplyFallback": fallbackOutcome(
                root: stock,
                multiplyProperty: "xrayMultiply",
                definitions: [fallbackDefinition(
                    name: "multiply", authoredValue: .scalar(1.5)
                )]
            ),
            "bothFallback": fallbackOutcome(
                root: stock,
                sizeProperty: "xraySize",
                multiplyProperty: "xrayMultiply",
                definitions: [
                    fallbackDefinition(name: "size", authoredValue: .scalar(0.25)),
                    fallbackDefinition(name: "multiply", authoredValue: .scalar(1.5)),
                ]
            ),
            "sharedKeyBothFallback": fallbackOutcome(
                root: stock,
                sizeProperty: "xrayShared",
                multiplyProperty: "xrayShared",
                definitions: [
                    fallbackDefinition(name: "size", authoredValue: .scalar(0.25)),
                    fallbackDefinition(name: "multiply", authoredValue: .scalar(1.5)),
                ]
            ),
            "sharedKeyBothLive": fallbackOutcome(
                root: stock,
                sizeProperty: "xrayShared",
                multiplyProperty: "xrayShared",
                producers: [
                    fallbackProducer("xrayShared", name: "size"),
                    fallbackProducer("xrayShared", name: "multiply"),
                ]
            ),
            "sizeFallbackMultiplyLive": fallbackOutcome(
                root: stock,
                sizeProperty: "xraySize",
                multiplyProperty: "xrayMultiply",
                producers: [fallbackProducer("xrayMultiply", name: "multiply")],
                definitions: [fallbackDefinition(
                    name: "size", authoredValue: .scalar(0.25)
                )]
            ),
            "sizeLiveMultiplyFallback": fallbackOutcome(
                root: stock,
                sizeProperty: "xraySize",
                multiplyProperty: "xrayMultiply",
                producers: [fallbackProducer("xraySize", name: "size")],
                definitions: [fallbackDefinition(
                    name: "multiply", authoredValue: .scalar(1.5)
                )]
            ),
            "sameSignZeroFallback": fallbackOutcome(
                root: stock,
                sizeFallback: -0.0,
                sizeProperty: "xraySize",
                definitions: [fallbackDefinition(
                    name: "size", authoredValue: .scalar(-0.0)
                )]
            ),
            "startupFallback": fallbackOutcome(
                root: stock,
                effectVisible: false,
                sizeProperty: "xraySize",
                producers: [visibility],
                definitions: [fallbackDefinition(
                    name: "size", authoredValue: .scalar(0.25)
                )],
                startupTargets: [visibility.target]
            ),
            "ownerPartitionTargetNames": ownerPartitionTargetNames(),
            "missingDefinitionRemainders": [
                fallbackOutcome(root: stock, sizeProperty: "xraySize"),
                fallbackOutcome(
                    root: stock,
                    sizeProperty: "xraySize",
                    multiplyProperty: "xrayMultiply",
                    definitions: [fallbackDefinition(
                        name: "size", authoredValue: .scalar(0.25)
                    )]
                ),
            ],
            "definitionIdentityRemainders": [
                fallbackOutcome(
                    root: stock,
                    sizeProperty: "xraySize",
                    definitions: [fallbackDefinition(
                        name: "size",
                        target: fallbackTarget(passIndex: 1, name: "size"),
                        authoredValue: .scalar(0.25)
                    )]
                ),
                fallbackOutcome(
                    root: stock,
                    sizeProperty: "xraySize",
                    definitions: [fallbackDefinition(
                        name: "size",
                        target: fallbackTarget(name: "otherSize"),
                        authoredValue: .scalar(0.25)
                    )]
                ),
                fallbackOutcome(
                    root: stock,
                    sizeProperty: "xraySize",
                    definitions: [fallbackDefinition(
                        name: "size",
                        target: fallbackTarget(layer: layerID + 1, name: "size"),
                        authoredValue: .scalar(0.25)
                    )]
                ),
                fallbackOutcome(
                    root: stock,
                    sizeProperty: "xraySize",
                    definitions: [fallbackDefinition(
                        name: "size",
                        target: fallbackTarget(effectIndex: 1, name: "size"),
                        authoredValue: .scalar(0.25)
                    )]
                ),
            ],
            "definitionValueRemainders": [
                fallbackOutcome(
                    root: stock,
                    sizeProperty: "xraySize",
                    definitions: [fallbackDefinition(
                        name: "size", valueType: .vector2,
                        authoredValue: .vector2(0.25, 0.25)
                    )]
                ),
                fallbackOutcome(
                    root: stock,
                    sizeProperty: "xraySize",
                    definitions: [fallbackDefinition(
                        name: "size", valueType: .scalar,
                        authoredValue: .vector2(0.25, 0.25)
                    )]
                ),
                fallbackOutcome(
                    root: stock,
                    sizeProperty: "xraySize",
                    definitions: [fallbackDefinition(
                        name: "size", authoredValue: .scalar(.nan)
                    )]
                ),
                fallbackOutcome(
                    root: stock,
                    sizeProperty: "xraySize",
                    definitions: [fallbackDefinition(
                        name: "size", authoredValue: .scalar(0.31)
                    )]
                ),
                fallbackOutcome(
                    root: stock,
                    sizeFallback: -0.0,
                    sizeProperty: "xraySize",
                    definitions: [fallbackDefinition(
                        name: "size", authoredValue: .scalar(0.0)
                    )]
                ),
            ],
            "duplicateDefinitionRemainders": [
                fallbackOutcome(
                    root: stock,
                    sizeProperty: "xraySize",
                    definitions: [
                        fallbackDefinition(name: "size", authoredValue: .scalar(0.25)),
                        fallbackDefinition(name: "size", authoredValue: .scalar(0.25)),
                    ]
                ),
                fallbackOutcome(
                    root: stock,
                    sizeProperty: "xraySize",
                    definitions: [
                        fallbackDefinition(name: "size", authoredValue: .scalar(0.25)),
                        fallbackDefinition(name: "size", authoredValue: .scalar(0.31)),
                    ]
                ),
            ],
            "rangeRemainders": [
                fallbackOutcome(
                    root: stock,
                    sizeFallback: 1.25,
                    sizeProperty: "xraySize",
                    definitions: [fallbackDefinition(
                        name: "size", authoredValue: .scalar(1.25)
                    )]
                ),
                fallbackOutcome(
                    root: stock,
                    multiplyFallback: 10.5,
                    multiplyProperty: "xrayMultiply",
                    definitions: [fallbackDefinition(
                        name: "multiply", authoredValue: .scalar(10.5)
                    )]
                ),
            ],
            "producerConflictRemainders": [
                fallbackOutcome(
                    root: stock,
                    sizeProperty: "xraySize",
                    producers: [fallbackProducer(
                        "xraySize", name: "size", type: .vector2
                    )],
                    definitions: [fallbackDefinition(
                        name: "size", authoredValue: .scalar(0.25)
                    )]
                ),
                fallbackOutcome(
                    root: stock,
                    sizeProperty: "xraySize",
                    producers: [fallbackProducer("otherSize", name: "size")],
                    definitions: [fallbackDefinition(
                        name: "size", authoredValue: .scalar(0.25)
                    )]
                ),
                fallbackOutcome(
                    root: stock,
                    sizeProperty: "xraySize",
                    producers: [fallbackProducer(
                        "xraySize", name: "size", passIndex: 1
                    )],
                    definitions: [fallbackDefinition(
                        name: "size", authoredValue: .scalar(0.25)
                    )]
                ),
                fallbackOutcome(
                    root: stock,
                    sizeProperty: "xraySize",
                    producers: [
                        fallbackProducer("xraySize", name: "size"),
                        fallbackProducer("otherSize", name: "size"),
                    ],
                    definitions: [fallbackDefinition(
                        name: "size", authoredValue: .scalar(0.25)
                    )]
                ),
                fallbackOutcome(
                    root: stock,
                    sizeProperty: "xrayShared",
                    multiplyProperty: "xrayShared",
                    producers: [fallbackProducer("xrayShared", name: "size")],
                    definitions: [fallbackDefinition(
                        name: "multiply", authoredValue: .scalar(1.5)
                    )]
                ),
            ],
            "wrapperAndScriptRemainders": [
                fallbackOutcome(
                    root: stock,
                    sizeProperty: "xraySize",
                    definitions: [fallbackDefinition(
                        name: "size", authoredValue: .scalar(0.25)
                    )],
                    extraSizeBindingKey: true
                ),
                fallbackOutcome(
                    root: stock,
                    sizeProperty: "xraySize",
                    definitions: [fallbackDefinition(
                        name: "size", authoredValue: .scalar(0.25)
                    )],
                    sizeScript: "return 0.5;"
                ),
            ],
'''

base_harness = BASE["HARNESS"]
for marker, label in (
    (FUNCTION_MARKER, "function"),
    (RESULT_MARKER, "result"),
):
    if base_harness.count(marker) != 1:
        raise RuntimeError(f"X-Ray owner harness {label} marker drifted")

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


class SceneXRayAuthoredFallbackOwnerAdmissionTests(_Base):
    FALLBACK_REVOKED = (
        "rejected:current-stock-authored-fallback-scalar-"
        "owner-revoked-to-material-program"
    )
    STARTUP_FALLBACK_REVOKED = (
        "rejected:startup-inactive-direct-bool-current-stock-"
        "authored-fallback-scalar-owner-revoked-to-material-program"
    )
    LIVE_REVOKED = (
        "rejected:current-stock-scalar-owner-revoked-to-material-program"
    )

    def test_static_live_and_fallback_combinations_revoke_atomically(self) -> None:
        for key in (
            "sizeFallbackMultiplyStatic",
            "sizeStaticMultiplyFallback",
            "bothFallback",
            "sharedKeyBothFallback",
            "sizeFallbackMultiplyLive",
            "sizeLiveMultiplyFallback",
            "sameSignZeroFallback",
        ):
            with self.subTest(key=key):
                self.assertEqual(self.result[key], self.FALLBACK_REVOKED)
        self.assertEqual(self.result["sharedKeyBothLive"], self.LIVE_REVOKED)
        self.assertEqual(
            self.result["startupFallback"],
            self.STARTUP_FALLBACK_REVOKED,
        )

    def test_retained_owner_suppresses_only_definition_only_targets(self) -> None:
        self.assertEqual(
            self.result["ownerPartitionTargetNames"],
            [[], ["multiply"], ["multiply", "size"]],
        )

    def test_missing_or_wrong_identity_definitions_retain_incumbent(self) -> None:
        self.assertEqual(self.result["missingDefinitionRemainders"], ["accepted"] * 2)
        self.assertEqual(self.result["definitionIdentityRemainders"], ["accepted"] * 4)

    def test_invalid_duplicate_or_bit_drifted_definitions_retain_incumbent(
        self,
    ) -> None:
        self.assertEqual(self.result["definitionValueRemainders"], ["accepted"] * 5)
        self.assertEqual(self.result["duplicateDefinitionRemainders"], ["accepted"] * 2)

    def test_exact_but_out_of_range_values_fail_closed_without_revocation(
        self,
    ) -> None:
        self.assertEqual(self.result["rangeRemainders"], ["rejected"] * 2)

    def test_conflicting_producers_and_scripts_retain_incumbent(
        self,
    ) -> None:
        self.assertEqual(self.result["producerConflictRemainders"], ["accepted"] * 5)
        self.assertEqual(
            self.result["wrapperAndScriptRemainders"],
            [self.FALLBACK_REVOKED, "accepted"],
        )


del _Base


if __name__ == "__main__":
    import unittest

    unittest.main()
