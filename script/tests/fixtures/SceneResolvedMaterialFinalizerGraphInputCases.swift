// Dormant graph inputs, self-composite overrides, and exact effect ingress.
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

func sameLayerCompositeOverrideTokens(_ device: MTLDevice) -> [String: String] {
    var result: [String: String] = [:]
    for (variant, layerID, coordinates, sampling, asset) in [
        ("original", 42, "v_TexCoord", "texSample2D", "textures/idle-source-default.tex"),
        ("renamed", 947, "uvUnseen", "texture2D", "fixtures/renamed-idle.tex")
    ] {
        let input = Graph.TextureIdentity(kind: .layerSource, layerID: layerID, effect: nil, name: nil)
        let owner = Graph.EffectKey(layerID: layerID, effectIndex: 0, descriptorID: "self-override-\(variant)")
        let output = Graph.TextureIdentity(kind: .effectOutput, layerID: layerID, effect: owner, name: nil)
        let path = SceneVFSAssetPath(asset)!
        let assetID = SceneAssetTextureIdentity(path: path, purpose: .straightAlbedo)
        let defaultResource = readyStatus(
            device, identity: .asset(assetID), purpose: .straightAlbedo,
            content: .color(.resolved(.straightAlpha))
        )
        let graphPublication = publication(
            device, requestIdentity: .graph(input),
            candidateIdentity: .provider(.graph(
                allocationGeneration: 1, physicalToken: "self-\(variant)"
            ))
        )
        let graphReady = SceneFrameTextureLookupStatus.ready(.init(
            publication: graphPublication, resourceGeneration: 1
        ))
        func named(
            _ id: Int, _ member: SceneNamedTextureReference.Variant = .secondary
        ) -> Template.TextureCandidate {
            .init(reference: .provider(.namedLayerTarget(.init(
                providerLayerID: id, variant: member
            ))), provenance: .instance)
        }
        func observe(
            _ name: String, _ candidates: [Template.TextureCandidate]?,
            binding: Graph.TextureIdentity? = nil, prepared: Bool = true
        ) {
            let shader = contract(
                revision: "self-\(variant)-\(name)", uniformMetadata: nil, semanticProbes: false,
                vertexSourceOverride: """
                attribute vec3 a_Position;
                attribute vec2 a_TexCoord;
                varying vec2 \(coordinates);
                void main() {
                    \(coordinates) = a_TexCoord;
                    gl_Position = vec4(a_Position, 1.0);
                }
                """,
                fragmentSourceOverride: """
                varying vec2 \(coordinates);
                uniform sampler2D g_Texture0; // {"default":"\(asset)","material":"albedo"}
                void main() {
                    vec4 color\(variant) = \(sampling)(g_Texture0, (\(coordinates).xy));
                    gl_FragColor = color\(variant);
                }
                """)
            var slots = Array<Template.TextureSlot?>(repeating: nil, count: 8)
            if let candidates { slots[0] = .init(index: 0, candidates: candidates) }
            let value = template(shader, includePrimaryCandidate: false,
                graphBindingsOverride: binding == nil ? [] : [.init(slot: 0, texture: .layerSource)],
                textureSlotsOverride: slots, effectContext: .init(key: owner, input: input))
            let prefix = "self-\(variant):\(name)"
            guard case let .success(cache) = SceneResolvedMaterialVariantCache.launchValidated(
                template: value, maximumVariantCount: 8
            ) else { result[prefix + ":source"] = "launch-failed"; return }
            if prepared {
                guard case .success = cache.precompileLaunchEnvelope(
                    implicitFramebufferIdentity: input,
                    graphTextureContentFacts: [input: .color(.resolved(.premultipliedAlpha))],
                    assetStates: [assetID: .ready(.color(.resolved(.straightAlpha)))]
                ) else { result[prefix + ":source"] = "prepare-failed"; return }
            }
            let effect = Graph.Effect(
                key: owner, definitionPath: "effects/self-\(variant).json",
                input: input, output: output, nodeIndices: [0]
            )
            let bindings: [Graph.Binding] = binding.map {
                [.init(slot: 0, authoredName: "previous", texture: $0, conditions: nil)]
            } ?? []
            let node = Graph.Node(
                nodeIndex: 0, effect: owner, definitionPassIndex: 0, materialOrdinal: 0,
                instancePassIndex: 0, kind: .material, materialPath: "materials/self-\(variant).json",
                materialPassID: "0", target: output, bindings: bindings,
                commandSource: nil, commandTarget: nil, compose: nil, conditions: nil
            )
            result[prefix + ":source"] = cache.capturedMainTargetSourceSlot(
                node: node, effect: effect
            ).map(String.init) ?? "none"
            result[prefix + ":internal"] = String(cache.supportsCapturedMainTargetInternalProgram(
                node: node, effect: effect
            ))
            guard name == "override" || name == "default" else { return }
            for (statusName, status) in [("ready", graphReady), ("pending", .pending),
                ("incomplete", .incomplete(.publication(graphPublication, resourceGeneration: 2)))] {
                if name == "default" && statusName != "ready" { continue }
                guard case let .success(frame) = SceneResolvedMaterialFrameSnapshot.validated(
                    textureSnapshot: snapshot(device, kind: .missing, additionalEntries: [
                        .graph(input): status, .asset(assetID): defaultResource
                    ]),
                    dynamicSnapshot: dynamicSnapshot(frameIndex: 1, source: nil),
                    frameInputs: frameInputs(frameIndex: 1)
                ) else { result[prefix + ":" + statusName] = "frame-failed"; continue }
                let finalized = SceneResolvedMaterialProgramFinalizer.finalize(
                    frame.finalizationInput(
                        template: value, layerID: layerID, renderSize: CGSize(width: 640, height: 360),
                        modelViewProjection: matrix_identity_float4x4, layerModelMatrix: layerModelMatrix,
                        effectOutputModelViewProjection: effectOutputModelViewProjection,
                        effectTextureProjectionMatrixInverse: effectProjectionInverse,
                        implicitFramebufferIdentity: input
                    ), variantCache: cache
                )
                var token = failureToken(finalized)
                if case let .success(program) = finalized, let slot = program.textureSlots[0] {
                    if name == "default" {
                        token = slot.reference == .asset(path) && slot.registryIdentity == .asset(assetID)
                            && slot.graphInputSourceFact == nil
                            && slot.diagnosticSelectionProvenance == .shaderDefault
                            ? "asset-default" : "binding-mismatch"
                    } else if let fact = slot.graphInputSourceFact {
                        token = slot.reference == .graph(input) && slot.registryIdentity == .graph(input)
                            && fact.slot == 0 && fact.inputIdentity == input
                            && fact.provenance == .sameLayerCompositeDefault
                            && slot.diagnosticSelectionProvenance == .authored(.instance)
                            && fact.selectionProvenance == .authored(.instance)
                            && program.semanticIdentity.textureSlots[0]?.graphInputSource == fact
                            && program.exactIdentity.textureSlots[0]?.graphInputSource == fact
                            ? "graph-ingress" : "binding-mismatch"
                    } else { token = "fact-missing" }
                }
                result[prefix + ":" + statusName] = token
            }
        }
        observe("override", [named(layerID)])
        observe("default", nil)
        guard variant == "original" else { continue }
        observe("chain", [named(layerID, .primary), named(layerID)])
        observe("foreign", [named(layerID + 1)])
        observe("mixed-foreign", [named(layerID + 1), named(layerID)])
        observe("mixed-asset", [.init(reference: .asset(path), provenance: .material), named(layerID)])
        observe("previous", [.init(reference: .graph(input), provenance: .explicitBinding)], binding: input)
        observe("conflict", [named(layerID)], binding: .init(kind: .layerSource, layerID: layerID + 1, effect: nil, name: nil))
        observe("unprepared", [named(layerID)], prepared: false)
    }
    return result
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
