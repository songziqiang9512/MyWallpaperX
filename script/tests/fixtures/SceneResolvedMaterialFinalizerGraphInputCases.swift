// Dormant graph inputs, exact terminal capture, and active effect ingress.
import Foundation
import Metal
import simd

func dormantGraphInputFactTokens(
    _ device: MTLDevice
) -> [String: String] {
    func shader(_ slot: Int, revision: String) -> SceneShaderContract {
        contract(
            revision: revision,
            uniformMetadata: nil,
            semanticProbes: false,
            fragmentSourceOverride: """
            varying vec2 v_TexCoord;
            uniform sampler2D g_Texture\(slot); // {"material":"Arbitrary \(revision)","label":"Random label \(slot)","hidden":true}
            void main() {
                gl_FragColor = texSample2D(
                    g_Texture\(slot),
                    v_TexCoord.xy
                );
            }
            """
        )
    }
    let effect = Graph.EffectKey(
        layerID: fixtureLayerID,
        effectIndex: 0,
        descriptorID: "fixture-dormant-arbitrary"
    )
    let context = Template.EffectContext(key: effect, input: graphTexture())
    let fallbackGraphFactPreserved: Bool = {
        let shader = shader(0, revision: "dormant-default-boundary")
        let value = template(
            shader,
            includePrimaryCandidate: false,
            effectContext: context
        )
        guard let samplers = try? SceneResolvedMaterialShaderSchema
                .unconditionalSamplers(value) else { return false }
        let sourceFacts = SceneResolvedMaterialShaderSchema
            .graphInputSourceSlotFacts(
                template: value,
                samplers: samplers,
                inputIdentity: graphTexture(),
                sourceColorTransfer: .straightAlphaPreserving(
                    textureSlot: 0
                )
            )
        let fallbackFacts = SceneResolvedMaterialShaderSchema
            .graphInputSourceSlotFacts(
                template: value,
                samplers: samplers,
                inputIdentity: graphTexture(),
                sourceColorTransfer: .defaultStraightColorBoundary(
                    textureSlots: [0]
                ),
                frontendBindings: [
                    .init(
                        name: "g_Texture0",
                        slot: 0,
                        channelUse: .wholeVector
                    )
                ]
            )
        return sourceFacts == fallbackFacts
            && fallbackFacts[0]?.provenance
                == .dormantUnresolvedMaterialAlias
    }()
    func result(_ slot: Int) -> Result<Program, SceneResolvedMaterialFailure> {
        finalize(
            shader: shader(slot, revision: "dormant-slot-\(slot)"),
            device: device,
            slot: slot,
            includePrimaryCandidate: false,
            implicitFramebufferIdentity: graphTexture(),
            effectContext: context
        )
    }
    func token(
        _ result: Result<Program, SceneResolvedMaterialFailure>,
        slot expectedSlot: Int
    ) -> String {
        guard case let .success(program) = result else {
            return failureToken(result)
        }
        guard
              let slot = program.textureSlots[expectedSlot],
              case let .graph(reference) = slot.reference,
              let fact = slot.graphInputSourceFact,
              fact.slot == expectedSlot,
              fact.inputIdentity == graphTexture(),
              fact.provenance == .dormantUnresolvedMaterialAlias,
              slot.diagnosticSelectionProvenance
                == .dormantUnresolvedMaterialGraphInput,
              program.semanticIdentity.textureSlots[expectedSlot]?
                .graphInputSource == fact,
              program.exactIdentity.textureSlots[expectedSlot]?
                .graphInputSource == fact else { return "fact-missing" }
        return reference == graphTexture()
            && program.frontendProgram.textureBindings.map(\.slot)
                == [expectedSlot]
            ? "proven" : "identity-mismatch"
    }
    return [
        "defaultBoundaryPreservesGraphFact": fallbackGraphFactPreserved
            ? "preserved" : "diverged",
        "arbitraryHiddenKeySlot0": token(result(0), slot: 0),
        "unseenArbitraryHiddenKeySlot3": token(result(3), slot: 3),
    ]
}

func capturedMainInternalTerminalTokens() -> [String: Bool] {
    func identity(
        kind: Graph.TextureKind,
        effect: Graph.EffectKey? = nil,
        name: String? = nil
    ) -> Graph.TextureIdentity {
        .init(
            kind: kind,
            layerID: fixtureLayerID,
            effect: effect,
            name: name
        )
    }
    let key = Graph.EffectKey(
        layerID: fixtureLayerID,
        effectIndex: 4,
        descriptorID: "fixture-captured-main-terminal"
    )
    let foreignKey = Graph.EffectKey(
        layerID: fixtureLayerID,
        effectIndex: 5,
        descriptorID: "fixture-foreign-terminal"
    )
    let input = identity(kind: .layerSource)
    let intermediate = identity(
        kind: .framebuffer,
        effect: key,
        name: "fixture-terminal-intermediate"
    )
    let output = identity(kind: .effectOutput, effect: key)
    let foreignOutput = identity(kind: .effectOutput, effect: foreignKey)
    let foreignFramebuffer = identity(
        kind: .framebuffer,
        effect: foreignKey,
        name: "fixture-foreign-intermediate"
    )
    let context = Template.EffectContext(key: key, input: input)
    let value = template(
        contract(
            revision: "captured-main-internal-terminal",
            uniformMetadata: nil,
            semanticProbes: false
        ),
        primaryReference: .graph(intermediate),
        primaryGraphTextureRole: .framebuffer,
        graphBindingsOverride: [.init(slot: 0, texture: .framebuffer)],
        effectContext: context
    )
    guard case let .success(cache) = SceneResolvedMaterialVariantCache
            .launchValidated(template: value, maximumVariantCount: 8),
          case .success = cache.precompileLaunchEnvelope(
              implicitFramebufferIdentity: input
          ) else {
        return ["setup": false]
    }
    let effect = Graph.Effect(
        key: key,
        definitionPath: "effects/fixture-captured-main-terminal.json",
        input: input,
        output: output,
        nodeIndices: [0]
    )
    func node(
        target: Graph.TextureIdentity?,
        binding: Graph.TextureIdentity = intermediate
    ) -> Graph.Node {
        .init(
            nodeIndex: 0,
            effect: key,
            definitionPassIndex: 0,
            materialOrdinal: 0,
            instancePassIndex: 0,
            kind: .material,
            materialPath: "materials/fixture-captured-main-terminal.json",
            materialPassID: "0",
            target: target,
            bindings: [
                .init(
                    slot: 0,
                    authoredName: "intermediate",
                    texture: binding,
                    conditions: nil
                ),
            ],
            commandSource: nil,
            commandTarget: nil,
            compose: nil,
            conditions: nil
        )
    }
    let terminal = node(target: output)
    let forgedEffect = Graph.Effect(
        key: key,
        definitionPath: effect.definitionPath,
        input: input,
        output: foreignOutput,
        nodeIndices: effect.nodeIndices
    )
    return [
        "exactEffectOutputAccepted":
            cache.supportsCapturedMainTargetInternalProgram(
                node: terminal,
                effect: effect
            ),
        "terminalRemainsInternalOnly":
            cache.capturedMainTargetSourceSlot(
                node: terminal,
                effect: effect
            ) == nil,
        "foreignEffectOutputRejected":
            !cache.supportsCapturedMainTargetInternalProgram(
                node: node(target: foreignOutput),
                effect: effect
            ),
        "foreignFramebufferBindingRejected":
            !cache.supportsCapturedMainTargetInternalProgram(
                node: node(target: output, binding: foreignFramebuffer),
                effect: effect
            ),
        "forgedEffectOutputRejected":
            !cache.supportsCapturedMainTargetInternalProgram(
                node: terminal,
                effect: forgedEffect
            ),
        "missingTargetRejected":
            !cache.supportsCapturedMainTargetInternalProgram(
                node: node(target: nil),
                effect: effect
            ),
    ]
}

func admittedEffectIngressTokens(
    _ device: MTLDevice
) -> [String: String] {
    func identity(
        kind: Graph.TextureKind,
        layerID: Int = fixtureLayerID,
        effect: Graph.EffectKey? = nil,
        name: String? = nil
    ) -> Graph.TextureIdentity {
        .init(kind: kind, layerID: layerID, effect: effect, name: name)
    }
    let owner = Graph.EffectKey(
        layerID: fixtureLayerID,
        effectIndex: 7,
        descriptorID: "fixture-active-after-disabled"
    )
    func token(
        _ input: Graph.TextureIdentity,
        contextInput: Graph.TextureIdentity? = nil,
        revision: String
    ) -> String {
        let resolvedContextInput = contextInput ?? input
        let snapshotIdentity = SceneFrameTextureIdentity.graph(input)
        return failureToken(finalize(
            shader: contract(
                revision: revision,
                samplerMetadata: #"{"material":"framebuffer","hidden":true}"#,
                uniformMetadata: nil,
                semanticProbes: false
            ),
            device: device,
            includePrimaryCandidate: false,
            additionalEntries: [
                snapshotIdentity: .ready(.init(
                    publication: publication(
                        device,
                        requestIdentity: snapshotIdentity,
                        candidateIdentity: .provider(.graph(
                            allocationGeneration: 9,
                            physicalToken: "fixture-admitted-ingress"
                        ))
                    ),
                    resourceGeneration: 9
                )),
            ],
            implicitFramebufferIdentity: input,
            effectContext: .init(key: owner, input: resolvedContextInput)
        ))
    }
    let prior = Graph.EffectKey(
        layerID: fixtureLayerID,
        effectIndex: 2,
        descriptorID: "fixture-prior-active"
    )
    return [
        "layerSourceAfterDisabledRawEffects": token(
            identity(kind: .layerSource),
            revision: "active-ingress-layer-source-gap"
        ),
        "priorActiveOutputWithRawOrdinalGap": token(
            identity(kind: .effectOutput, effect: prior),
            revision: "active-ingress-effect-output-gap"
        ),
        "contextIdentityMismatch": token(
            identity(kind: .effectOutput, effect: prior),
            contextInput: identity(kind: .layerSource),
            revision: "active-ingress-context-mismatch"
        ),
        "wrongLayer": token(
            identity(kind: .layerSource, layerID: fixtureLayerID + 1),
            revision: "active-ingress-wrong-layer"
        ),
        "namedLayerSource": token(
            identity(kind: .layerSource, name: "forged"),
            revision: "active-ingress-named-layer-source"
        ),
        "selfOutput": token(
            identity(kind: .effectOutput, effect: owner),
            revision: "active-ingress-self-output"
        ),
    ]
}
