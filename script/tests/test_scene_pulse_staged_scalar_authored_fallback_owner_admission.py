#!/usr/bin/env python3
"""Executable Pulse staged-scalar authored-fallback owner admission."""

from __future__ import annotations

from pathlib import Path
import runpy


BASE = runpy.run_path(
    str(Path(__file__).with_name(
        "test_scene_pulse_authored_fallback_owner_admission.py"
    ))
)
_Base = BASE["ScenePulseAuthoredFallbackOwnerAdmissionTests"]

FUNCTION_MARKER = "\n@main\nenum Harness {"
RESULT_MARKER = "        let result: [String: Any] = [\n"

STAGED_FUNCTIONS = r'''

private func stagedAuthoredValue(
    _ components: [Double]
) -> SceneDynamicValue {
    switch components.count {
    case 1:
        return .scalar(components[0])
    case 2:
        return .vector2(components[0], components[1])
    case 3:
        return .vector3(components[0], components[1], components[2])
    default:
        preconditionFailure("unsupported staged fallback component count")
    }
}

private func stagedExactFallbackOutcome(
    _ contracts: [SceneShaderContract],
    bindings: [Constant: String],
    fallbackOverrides: [Constant: [Double]]
) -> String {
    fallbackOutcome(
        contracts,
        bindings: bindings,
        fallbackOverrides: fallbackOverrides,
        definitions: fallbackOverrides.map { constant, components in
            fallbackDefinition(
                constant,
                authoredValue: stagedAuthoredValue(components)
            )
        }
    )
}

private func stagedReplacingFallbackWrapper(
    _ input: SceneEffectStageCompileInput,
    constant: Constant,
    bindingKeys: [String],
    scriptSource: String?
) -> SceneEffectStageCompileInput {
    let descriptor = input.descriptor
    let layer = descriptor.layers[0]
    let effect = layer.effects[0]
    let pass = effect.passes[0]
    var constants = pass.constantShaderValues
    let authored = constants[constant.rawValue]!
    constants[constant.rawValue] = .init(
        rawValue: authored.rawValue,
        valueKind: authored.valueKind,
        userBinding: authored.userBinding,
        userValueKind: authored.userValueKind,
        components: authored.components,
        timeline: authored.timeline,
        timelineDiagnostics: authored.timelineDiagnostics,
        scriptSource: scriptSource,
        bindingKeys: bindingKeys
    )
    var passes = effect.passes
    passes[0] = .init(
        passIndex: pass.passIndex,
        texturePaths: pass.texturePaths,
        textureSlots: pass.textureSlots,
        userTextureInputs: pass.userTextureInputs,
        combos: pass.combos,
        constantShaderValues: constants
    )
    var effects = layer.effects
    effects[0] = .init(
        id: effect.id,
        file: effect.file,
        visible: effect.visible,
        passes: passes
    )
    var layers = descriptor.layers
    layers[0] = .init(
        id: layer.id,
        contentKind: layer.contentKind,
        effects: effects
    )
    let replacement = SceneRenderDescriptor(
        layers: layers,
        materialPasses: descriptor.materialPasses,
        effectDefinitions: descriptor.effectDefinitions
    )
    return .init(
        stageGraph: input.stageGraph,
        authoredOrdinal: input.authoredOrdinal,
        effectKey: input.effectKey,
        definitionPath: input.definitionPath,
        inputRole: input.inputRole,
        descriptor: replacement,
        shaderContracts: input.shaderContracts,
        userPropertyProducers: input.userPropertyProducers,
        propertyDefinitions: input.propertyDefinitions,
        timelineDefinitions: input.timelineDefinitions,
        activeEffectLocalDirectBoolVisibilityTargets:
            input.activeEffectLocalDirectBoolVisibilityTargets,
        startupInactiveEffectVisibilityTargets:
            input.startupInactiveEffectVisibilityTargets,
        frameDrivenEffectVisibilityOwners:
            input.frameDrivenEffectVisibilityOwners
    )
}

private func stagedWrapperOutcome(
    _ contracts: [SceneShaderContract],
    bindingKeys: [String],
    scriptSource: String? = nil
) -> String {
    let input = fallbackInput(
        contracts: contracts,
        bindings: [.speed: "pulseSpeed"],
        fallbackOverrides: [.speed: [3]],
        definitions: [fallbackDefinition(
            .speed, authoredValue: .scalar(3)
        )]
    )
    return outcome(stagedReplacingFallbackWrapper(
        input,
        constant: .speed,
        bindingKeys: bindingKeys,
        scriptSource: scriptSource
    ))
}
'''

STAGED_RESULTS = r'''            "stagedStockScalarCombination":
                stagedExactFallbackOutcome(
                    contracts,
                    bindings: [
                        .speed: "pulseSpeed",
                        .amount: "pulseAmount",
                        .phase: "pulsePhase",
                    ],
                    fallbackOverrides: [
                        .speed: [3],
                        .amount: [1],
                        .phase: [0.5],
                    ]
                ),
            "stagedStockFragmentCombination": stagedExactFallbackOutcome(
                contracts,
                bindings: [
                    .speed: "pulseSpeed",
                    .amount: "pulseAmount",
                    .phase: "pulsePhase",
                    .noiseAmount: "pulseNoiseAmount",
                    .tintLow: "pulseTintLow",
                ],
                fallbackOverrides: [
                    .speed: [3],
                    .amount: [1],
                    .phase: [0.5],
                    .noiseAmount: [0.25],
                    .tintLow: [0.2, 0.3, 0.4],
                ]
            ),
            "stagedHistoricalPhase": legacyContracts.map {
                stagedExactFallbackOutcome(
                    $0,
                    bindings: [.phase: "pulsePhase"],
                    fallbackOverrides: [.phase: [0.5]]
                )
            },
            "stagedHistoricalNonPhase": [
                stagedExactFallbackOutcome(
                    legacyContracts[0],
                    bindings: [.speed: "pulseSpeed"],
                    fallbackOverrides: [.speed: [3]]
                ),
                stagedExactFallbackOutcome(
                    legacyContracts[1],
                    bindings: [.amount: "pulseAmount"],
                    fallbackOverrides: [.amount: [1]]
                ),
            ],
            "stagedMixedSource": fallbackOutcome(
                contracts,
                bindings: [
                    .speed: "pulseSpeed",
                    .amount: "pulseAmount",
                ],
                fallbackOverrides: [
                    .speed: [3],
                    .amount: [1],
                ],
                producers: [fallbackProducer(
                    .speed, propertyKey: "pulseSpeed"
                )],
                definitions: [fallbackDefinition(
                    .amount, authoredValue: .scalar(1)
                )]
            ),
            "stagedDefinitionRemainders": [
                fallbackOutcome(
                    contracts,
                    bindings: [.speed: "pulseSpeed"],
                    fallbackOverrides: [.speed: [3]]
                ),
                fallbackOutcome(
                    contracts,
                    bindings: [.speed: "pulseSpeed"],
                    fallbackOverrides: [.speed: [3]],
                    definitions: [
                        fallbackDefinition(
                            .speed, authoredValue: .scalar(3)
                        ),
                        fallbackDefinition(
                            .speed, authoredValue: .scalar(3)
                        ),
                    ]
                ),
                fallbackOutcome(
                    contracts,
                    bindings: [.speed: "pulseSpeed"],
                    fallbackOverrides: [.speed: [3]],
                    definitions: [fallbackDefinition(
                        .speed,
                        target: fallbackTarget(.speed, passIndex: 1),
                        authoredValue: .scalar(3)
                    )]
                ),
                fallbackOutcome(
                    contracts,
                    bindings: [.speed: "pulseSpeed"],
                    fallbackOverrides: [.speed: [3]],
                    definitions: [fallbackDefinition(
                        .speed,
                        valueType: .vector2,
                        authoredValue: .vector2(3, 3)
                    )]
                ),
                fallbackOutcome(
                    contracts,
                    bindings: [.speed: "pulseSpeed"],
                    fallbackOverrides: [.speed: [3]],
                    definitions: [fallbackDefinition(
                        .speed, authoredValue: .scalar(.nan)
                    )]
                ),
                fallbackOutcome(
                    contracts,
                    bindings: [.speed: "pulseSpeed"],
                    fallbackOverrides: [.speed: [3]],
                    definitions: [fallbackDefinition(
                        .speed, authoredValue: .scalar(3.0000000000000004)
                    )]
                ),
            ],
            "stagedStockVertexPhaseDomain": stagedExactFallbackOutcome(
                contracts,
                bindings: [.phase: "pulsePhase"],
                fallbackOverrides: [.phase: [2]]
            ),
            "stagedWrapperAndScript": [
                stagedWrapperOutcome(
                    contracts,
                    bindingKeys: ["extra", "user", "value"]
                ),
                stagedWrapperOutcome(
                    contracts,
                    bindingKeys: ["script", "user", "value"],
                    scriptSource: "export function update() {}"
                ),
            ],
'''

base_globals = _Base.setUpClass.__func__.__globals__
base_harness = base_globals["HARNESS"]
for marker, label in (
    (FUNCTION_MARKER, "function"),
    (RESULT_MARKER, "result"),
):
    if base_harness.count(marker) != 1:
        raise RuntimeError(f"Pulse staged fallback harness {label} marker drifted")

base_globals["HARNESS"] = base_harness.replace(
    FUNCTION_MARKER,
    STAGED_FUNCTIONS + FUNCTION_MARKER,
    1,
).replace(
    RESULT_MARKER,
    RESULT_MARKER + STAGED_RESULTS,
    1,
)


class ScenePulseStagedScalarAuthoredFallbackOwnerAdmissionTests(_Base):
    STAGED_SCALAR_REVOKED = (
        "revoked:authored-fallback-profile-staged-scalar-"
        "owner-revoked-to-material-program"
    )
    STAGED_COMBINED_REVOKED = (
        "revoked:authored-fallback-profile-staged-scalar-vector3-"
        "owner-revoked-to-material-program"
    )

    def test_stock_staged_and_unseen_fragment_combination_revoke_owner(
        self,
    ) -> None:
        self.assertEqual(
            self.result["stagedStockScalarCombination"],
            self.STAGED_SCALAR_REVOKED,
        )
        self.assertEqual(
            self.result["stagedStockFragmentCombination"],
            self.STAGED_COMBINED_REVOKED,
        )

    def test_historical_profiles_admit_only_exact_phase(self) -> None:
        self.assertEqual(
            self.result["stagedHistoricalPhase"],
            [self.STAGED_SCALAR_REVOKED] * 3,
        )
        self.assertEqual(
            self.result["stagedHistoricalNonPhase"],
            ["incumbent"] * 2,
        )

    def test_source_and_definition_drift_retain_owner(self) -> None:
        self.assertEqual(self.result["stagedMixedSource"], "incumbent")
        self.assertEqual(
            self.result["stagedDefinitionRemainders"],
            ["incumbent"] * 6,
        )

    def test_vertex_domain_and_wrapper_drift_retain_owner(self) -> None:
        self.assertEqual(
            self.result["stagedStockVertexPhaseDomain"],
            "incumbent",
        )
        self.assertEqual(
            self.result["stagedWrapperAndScript"],
            ["incumbent"] * 2,
        )


del _Base


if __name__ == "__main__":
    import unittest

    unittest.main()
