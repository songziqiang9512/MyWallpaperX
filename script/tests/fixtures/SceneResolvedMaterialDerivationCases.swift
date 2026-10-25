// Atomic derivation, identity, color transfer, and failure cases.
import Foundation
import Metal
import simd

@main
private enum Harness {
    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("{\"metalAvailable\":false}")
            return
        }
        let firstPrepared = prepared(revision: "revision-a")
        let firstSlot = textureSlot(device: device)
        let baseline = assemble(
            prepared: firstPrepared,
            textureSlots: slots(firstSlot)
        )!
        let scalarBaseline = assemble(
            prepared: firstPrepared,
            textureSlots: slots(firstSlot),
            outputStorage: .scalarRedUnorm
        )!
        let proceduralOpaque = assemble(
            prepared: prepared(
                revision: "procedural-opaque",
                fragment: proceduralOpaqueFragment
            ),
            textureSlots: slots()
        )

        let synonymState = assemble(
            prepared: firstPrepared,
            textureSlots: slots(firstSlot),
            renderState: state(synonym: true)
        )!
        let changedUniform = assemble(
            prepared: firstPrepared,
            textureSlots: slots(firstSlot),
            gain: 0.75
        )!
        let changedRevision = assemble(
            prepared: prepared(revision: "revision-b"),
            textureSlots: slots(firstSlot)
        )!
        let changedGraphRole = assemble(
            prepared: firstPrepared,
            textureSlots: slots(firstSlot),
            role: graphRole(effectInput: .effectOutput)
        )!
        let inactiveGraphBinding = assemble(
            prepared: firstPrepared,
            textureSlots: slots(firstSlot),
            role: .init(
                effectInput: .layerSource,
                effectOutput: .effectOutput,
                nodeTarget: .framebuffer,
                bindings: [
                    .init(slot: 0, texture: .framebuffer),
                    .init(slot: 1, texture: .layerSource),
                ]
            )
        )!
        let changedInstance = assemble(
            prepared: firstPrepared,
            textureSlots: slots(textureSlot(device: device, marker: 99))
        )!

        let missingSlot = assemble(
            prepared: firstPrepared,
            textureSlots: slots()
        ) == nil
        let wrongPurpose = assemble(
            prepared: firstPrepared,
            textureSlots: slots(textureSlot(
                device: device,
                expectedPurpose: .straightAlbedo
            ))
        ) == nil
        let mismatchedRegistryIdentity = assemble(
            prepared: firstPrepared,
            textureSlots: slots(textureSlot(
                device: device,
                registryIdentityOverride: .system(.init(
                    name: "wrong-provider",
                    purpose: .premultipliedColor
                ))
            ))
        ) == nil
        let mismatchedExactGraphIdentity = assemble(
            prepared: firstPrepared,
            textureSlots: slots(textureSlot(
                device: device,
                registryIdentityOverride: .graph(graphIdentity(marker: 99))
            ))
        ) == nil
        let reversedUniforms = assemble(
            prepared: firstPrepared,
            textureSlots: slots(firstSlot),
            reverseUniforms: true
        ) == nil
        let mismatchedDynamicSource = assemble(
            prepared: firstPrepared,
            textureSlots: slots(firstSlot),
            dynamic: (.timeline, .userProperty, [])
        ) == nil
        let authoredFallback = assemble(
            prepared: firstPrepared,
            textureSlots: slots(firstSlot),
            dynamic: (.timeline, .authored, [])
        )
        let changedSelectionProvenance = Program.TextureSlot(
            index: firstSlot.index,
            reference: firstSlot.reference,
            registryIdentity: firstSlot.registryIdentity,
            diagnosticSelectionProvenance: .shaderDefault,
            expectedPurpose: firstSlot.expectedPurpose,
            resource: firstSlot.resource
        )
        let provenanceVariant = assemble(
            prepared: firstPrepared,
            textureSlots: slots(changedSelectionProvenance)
        )!
        let authoredClampVariant = assemble(
            prepared: firstPrepared,
            textureSlots: slots(replacingSampling(
                firstSlot,
                with: .init(texFlags: 2)
            ))
        )!
        let unsupportedState = assemble(
            prepared: firstPrepared,
            textureSlots: slots(firstSlot),
            renderState: state(blending: "translucent")
        ) == nil
        let mismatchedGraphBinding = assemble(
            prepared: firstPrepared,
            textureSlots: slots(firstSlot),
            role: .init(
                effectInput: .layerSource,
                effectOutput: .effectOutput,
                nodeTarget: .framebuffer,
                bindings: [.init(slot: 0, texture: .layerSource)]
            )
        ) == nil
        let invalidGraphBindingSlot = assemble(
            prepared: firstPrepared,
            textureSlots: slots(firstSlot),
            role: .init(
                effectInput: .layerSource,
                effectOutput: .effectOutput,
                nodeTarget: .framebuffer,
                bindings: [.init(slot: 8, texture: .framebuffer)]
            )
        ) == nil
        let unresolvedPublication = assemble(
            prepared: firstPrepared,
            textureSlots: slots(textureSlot(
                device: device,
                content: .color(.unresolved)
            ))
        ) == nil
        let arithmeticPrepared = prepared(
            revision: "unresolved-transfer",
            fragment: """
            varying vec2 v_TexCoord;
            uniform sampler2D g_Texture0;
            uniform float g_Gain;
            void main() {
                gl_FragColor = texSample2D(g_Texture0, v_TexCoord) * g_Gain;
            }
            """
        )
        let unresolvedTransfer = assemble(
            prepared: arithmeticPrepared,
            textureSlots: slots(firstSlot)
        ) == nil
        let staleFrontendSchema = assemble(
            prepared: prepared(
                revision: "stale-frontend-schema",
                frontendSchemaVersion: SceneShaderVariantEnvironment.frontendSchemaVersion - 1
            ),
            textureSlots: slots(firstSlot)
        ) == nil

        let straightPrepared = prepared(
            revision: "straight-alpha-boundary",
            fragment: straightAlphaFragment
        )
        let straightPremultiplied = assemble(
            prepared: straightPrepared,
            textureSlots: slots(firstSlot)
        )
        let straightOpaque = assemble(
            prepared: straightPrepared,
            textureSlots: slots(textureSlot(
                device: device,
                content: .color(.resolved(.opaque))
            ))
        )
        let straightInputRejected = assemble(
            prepared: straightPrepared,
            textureSlots: slots(textureSlot(
                device: device,
                content: .color(.resolved(.straightAlpha))
            ))
        ) == nil
        let straightDataRejected = assemble(
            prepared: straightPrepared,
            textureSlots: slots(textureSlot(
                device: device,
                content: .data
            ))
        ) == nil

        let scanlinePrepared = prepared(
            revision: "scanline-uniform-rgb-mix",
            fragment: scanlineUniformRGBMixFragment
        )
        let scanlineRole = Template.GraphRole(
            effectInput: .layerSource,
            effectOutput: .effectOutput,
            nodeTarget: .effectOutput,
            bindings: [.init(slot: 0, texture: .layerSource)]
        )
        let scanlinePremultiplied = assemble(
            prepared: scanlinePrepared,
            textureSlots: slots(textureSlot(
                device: device,
                marker: 40,
                graphKind: .layerSource
            )),
            role: scanlineRole
        )
        let scanlineDataRejected = assemble(
            prepared: scanlinePrepared,
            textureSlots: slots(textureSlot(
                device: device,
                marker: 41,
                content: .data,
                graphKind: .layerSource
            )),
            role: scanlineRole
        ) == nil

        let maskedPrepared = prepared(
            revision: "masked-alpha-boundary",
            fragment: maskedAlphaFragment
        )
        let maskSlot = textureSlot(
            device: device,
            slot: 1,
            marker: 41,
            expectedPurpose: .mask,
            publishedPurpose: .mask,
            content: .data,
            reference: .asset(SceneVFSAssetPath("assets/mask.tex")!)
        )
        let maskedDataAccepted = assemble(
            prepared: maskedPrepared,
            textureSlots: slots(firstSlot, maskSlot)
        )
        let maskedColorRejected = assemble(
            prepared: maskedPrepared,
            textureSlots: slots(firstSlot, textureSlot(
                device: device,
                slot: 1,
                marker: 42,
                expectedPurpose: .straightAlbedo,
                publishedPurpose: .straightAlbedo,
                content: .color(.resolved(.straightAlpha)),
                reference: .asset(SceneVFSAssetPath("assets/second-color.tex")!)
            ))
        ) == nil

        let opaqueAlphaPrepared = prepared(
            revision: "opaque-alpha-preserving",
            fragment: opaqueAlphaPreservingFragment
        )
        let opaqueAlphaAccepted = assemble(
            prepared: opaqueAlphaPrepared,
            textureSlots: slots(textureSlot(
                device: device,
                content: .color(.resolved(.opaque))
            ))
        )
        let opaqueAlphaPremultipliedAccepted = assemble(
            prepared: opaqueAlphaPrepared,
            textureSlots: slots(firstSlot)
        )

        let wholeFilterPrepared = prepared(
            revision: "whole-color-unorm-filter",
            fragment: wholeColorFilterFragment
        )
        let wholeFilterAccepted = assemble(
            prepared: wholeFilterPrepared,
            textureSlots: slots(textureSlot(
                device: device,
                marker: 44,
                graphKind: .layerSource
            ), maskSlot),
            role: .init(
                effectInput: .layerSource,
                effectOutput: .effectOutput,
                nodeTarget: .effectOutput,
                bindings: [.init(slot: 0, texture: .layerSource)]
            )
        )
        let wholeFilterColorAuxiliaryRejected = assemble(
            prepared: wholeFilterPrepared,
            textureSlots: slots(textureSlot(
                device: device,
                marker: 45,
                graphKind: .layerSource
            ), textureSlot(
                device: device,
                slot: 1,
                marker: 43,
                expectedPurpose: .straightAlbedo,
                publishedPurpose: .straightAlbedo,
                content: .color(.resolved(.straightAlpha)),
                reference: .asset(SceneVFSAssetPath("assets/filter-color.tex")!)
            )),
            role: .init(
                effectInput: .layerSource,
                effectOutput: .effectOutput,
                nodeTarget: .effectOutput,
                bindings: [.init(slot: 0, texture: .layerSource)]
            )
        ) == nil
        let wholeFilterEffectOutputRejected = assemble(
            prepared: wholeFilterPrepared,
            textureSlots: slots(firstSlot, maskSlot),
            role: graphRole(effectInput: .effectOutput)
        ) == nil
        let wholeFilterFramebufferRejected = assemble(
            prepared: wholeFilterPrepared,
            textureSlots: slots(firstSlot, maskSlot),
            role: graphRole(effectInput: .layerSource)
        ) == nil
        let wholeFilterScalarFramebufferAccepted = assemble(
            prepared: wholeFilterPrepared,
            textureSlots: slots(firstSlot, maskSlot),
            role: graphRole(effectInput: .layerSource),
            outputStorage: .scalarRedUnorm
        )
        let wholeFilterScalarMismatchedBindingRejected = assemble(
            prepared: wholeFilterPrepared,
            textureSlots: slots(firstSlot, maskSlot),
            role: .init(
                effectInput: .layerSource,
                effectOutput: .effectOutput,
                nodeTarget: .framebuffer,
                bindings: [.init(slot: 0, texture: .layerSource)]
            ),
            outputStorage: .scalarRedUnorm
        ) == nil

        let twoSlotPrepared = prepared(
            revision: "two-color-inputs",
            fragment: """
            varying vec2 v_TexCoord;
            uniform sampler2D g_Texture0;
            uniform sampler2D g_Texture1;
            uniform float g_Gain;
            void main() {
                gl_FragColor = texSample2D(g_Texture0, v_TexCoord);
            }
            """
        )
        let secondSlot = textureSlot(
            device: device,
            slot: 1,
            marker: 2,
            expectedPurpose: .straightAlbedo,
            publishedPurpose: .straightAlbedo,
            content: .color(.resolved(.straightAlpha))
        )
        let nonGraphWithGraphBinding = assemble(
            prepared: twoSlotPrepared,
            textureSlots: slots(firstSlot, textureSlot(
                device: device,
                slot: 1,
                marker: 3,
                reference: .asset(SceneVFSAssetPath("assets/color.tex")!)
            )),
            role: .init(
                effectInput: .layerSource,
                effectOutput: .effectOutput,
                nodeTarget: .framebuffer,
                bindings: [
                    .init(slot: 0, texture: .framebuffer),
                    .init(slot: 1, texture: .layerSource),
                ]
            )
        ) == nil
        let ambiguousFramebufferRepresentation = assemble(
            prepared: twoSlotPrepared,
            textureSlots: slots(firstSlot, secondSlot)
        ) == nil
        let signalSlot = textureSlot(
            device: device,
            content: .color(.resolved(.independentAlphaSignal))
        )
        let preservingSignalProjection = SceneResolvedMaterialProgramDerivation
            .resolveColor(
                transfer: .independentAlphaSignalPreserving(textureSlot: 0),
                textureSlots: slots(signalSlot)
            )
        let preservingPremultipliedRejected = SceneResolvedMaterialProgramDerivation
            .resolveColor(
                transfer: .independentAlphaSignalPreserving(textureSlot: 0),
                textureSlots: slots(firstSlot)
            ) == nil
        let compositingProjection = SceneResolvedMaterialProgramDerivation.resolveColor(
            transfer: .independentAlphaSignalCompositing(
                signalSlot: 0,
                colorSlot: 1
            ),
            textureSlots: slots(signalSlot, textureSlot(
                device: device,
                slot: 1,
                marker: 2
            ))
        )
        let compositingDataAuxiliaryProjection = SceneResolvedMaterialProgramDerivation
            .resolveColor(
                transfer: .independentAlphaSignalCompositing(
                    signalSlot: 0,
                    colorSlot: 1
                ),
                textureSlots: slots(
                    signalSlot,
                    textureSlot(device: device, slot: 1, marker: 2),
                    textureSlot(
                        device: device,
                        slot: 3,
                        marker: 4,
                        expectedPurpose: .preservedChannels,
                        publishedPurpose: .preservedChannels,
                        content: .data,
                        reference: .asset(
                            SceneVFSAssetPath("gradient/gradient_fire")!
                        )
                    )
                )
            )
        let compositingColorAuxiliaryRejected = SceneResolvedMaterialProgramDerivation
            .resolveColor(
                transfer: .independentAlphaSignalCompositing(
                    signalSlot: 0,
                    colorSlot: 1
                ),
                textureSlots: slots(
                    signalSlot,
                    textureSlot(device: device, slot: 1, marker: 2),
                    textureSlot(
                        device: device,
                        slot: 3,
                        marker: 4,
                        reference: .asset(
                            SceneVFSAssetPath("assets/extra-color.tex")!
                        )
                    )
                )
            ) == nil
        let secondPremultipliedSlot = textureSlot(
            device: device,
            slot: 1,
            marker: 3
        )
        let interpolatedProjection = SceneResolvedMaterialProgramDerivation.resolveColor(
            transfer: .interpolatedColor(textureSlots: [0, 1]),
            textureSlots: slots(firstSlot, secondPremultipliedSlot)
        )
        let opaqueSlot = textureSlot(
            device: device,
            slot: 1,
            marker: 4,
            content: .color(.resolved(.opaque))
        )
        let interpolatedOpaquePremultipliedProjection =
            SceneResolvedMaterialProgramDerivation.resolveColor(
                transfer: .interpolatedColor(textureSlots: [0, 1]),
                textureSlots: slots(firstSlot, opaqueSlot)
            )
        let unrelatedFramebufferSlot = textureSlot(
            device: device,
            slot: 2,
            marker: 7,
            content: .color(.resolved(.straightAlpha))
        )
        let interpolatedWithUnrelatedFramebufferColor =
            SceneResolvedMaterialProgramDerivation.resolveColor(
                transfer: .interpolatedColor(textureSlots: [0, 1]),
                textureSlots: slots(
                    firstSlot, opaqueSlot, unrelatedFramebufferSlot
                )
            )
        let interpolatedDataRejected =
            SceneResolvedMaterialProgramDerivation.resolveColor(
                transfer: .interpolatedColor(textureSlots: [0, 1]),
                textureSlots: slots(
                    firstSlot,
                    textureSlot(
                        device: device,
                        slot: 1,
                        marker: 8,
                        content: .data
                    )
                )
            ) == nil
        let interpolatedIndependentSignalRejected =
            SceneResolvedMaterialProgramDerivation.resolveColor(
                transfer: .interpolatedColor(textureSlots: [0, 1]),
                textureSlots: slots(
                    firstSlot,
                    textureSlot(
                        device: device,
                        slot: 1,
                        marker: 9,
                        content: .color(
                            .resolved(.independentAlphaSignal)
                        )
                    )
                )
            ) == nil
        let interpolatedMismatchRejected = SceneResolvedMaterialProgramDerivation
            .resolveColor(
                transfer: .interpolatedColor(textureSlots: [0, 1]),
                textureSlots: slots(firstSlot, secondSlot)
            ) == nil
        let interpolatedUnsortedRejected = SceneResolvedMaterialProgramDerivation
            .resolveColor(
                transfer: .interpolatedColor(textureSlots: [1, 0]),
                textureSlots: slots(firstSlot, secondPremultipliedSlot)
            ) == nil
        let namedOverlay = textureSlot(
            device: device,
            slot: 1,
            marker: 21,
            content: .color(.resolved(.premultipliedAlpha)),
            reference: .provider(.namedLayerTarget(
                SceneNamedTextureReference(providerLayerID: 1321, variant: .primary)
            ))
        )
        let associatedOverNamedOverlayProjection =
            SceneResolvedMaterialProgramDerivation.resolveColor(
                transfer: .straightAlpha(textureSlot: 0),
                textureSlots: slots(firstSlot, namedOverlay),
                associatedOverOverlaySlot: 1,
                premultipliedColorInputSlots: [1]
            )
        let associatedOverColorOverlayWithoutFactRejected =
            SceneResolvedMaterialProgramDerivation.resolveColor(
                transfer: .straightAlpha(textureSlot: 0),
                textureSlots: slots(firstSlot, namedOverlay)
            ) == nil
        let associatedOverColorOverlayWrongSlotRejected =
            SceneResolvedMaterialProgramDerivation.resolveColor(
                transfer: .straightAlpha(textureSlot: 0),
                textureSlots: slots(firstSlot, namedOverlay),
                associatedOverOverlaySlot: 1,
                premultipliedColorInputSlots: [2]
            ) == nil

        var results: [String: Bool] = [
            "metalAvailable": true,
            "scalarOutputContractHasDistinctIdentity":
                baseline.semanticIdentity != scalarBaseline.semanticIdentity
                && scalarBaseline.semanticIdentity.outputContract == .scalarRedUnorm
                && scalarBaseline.outputContract == .scalarRedUnorm,
            "baselineAssembled": baseline.textureSlots.count == 8,
            "uniformLayoutMatchesDeclaredFields": baseline.uniformBytes.count
                == baseline.frontendProgram.uniformLayout.byteSize
                && baseline.frontendProgram.uniformLayout.fields.map(\.name)
                    == ["g_Gain", "mwxRenderSize", "mwxVertexCoordinates01", "mwxVertexCoordinates23"]
                && baseline.frontendProgram.uniformLayout.fields.filter {
                    $0.name == "mwxVertexCoordinates01" || $0.name == "mwxVertexCoordinates23"
                }.allSatisfy { field in
                    field.type == .float4
                        && field.offset >= 0 && field.offset + 16 <= baseline.uniformBytes.count
                        && baseline.uniformBytes.subdata(in: field.offset ..< field.offset + 16)
                            == data(field.name == "mwxVertexCoordinates01"
                                ? SIMD4<Float>(0, 1, 1, 1) : SIMD4<Float>(0, 0, 1, 0))
                },
            "rawStateSynonymSemantic": baseline.semanticIdentity
                == synonymState.semanticIdentity,
            "rawStateExcludedFromExact": baseline.exactIdentity
                == synonymState.exactIdentity,
            "uniformValueSemanticStable": baseline.semanticIdentity
                == changedUniform.semanticIdentity,
            "uniformValueChangesExact": baseline.exactIdentity
                != changedUniform.exactIdentity,
            "revisionTypedIRSemanticStable": baseline.semanticIdentity
                == changedRevision.semanticIdentity,
            "revisionChangesExact": baseline.exactIdentity
                != changedRevision.exactIdentity,
            "graphRoleChangesSemantic": baseline.semanticIdentity
                != changedGraphRole.semanticIdentity,
            "inactiveGraphBindingExcluded": baseline.semanticIdentity
                == inactiveGraphBinding.semanticIdentity,
            "instanceIdentitySemanticStable": baseline.semanticIdentity
                == changedInstance.semanticIdentity,
            "instanceIdentityChangesExact": baseline.exactIdentity
                != changedInstance.exactIdentity,
            "missingSlotRejected": missingSlot,
            "wrongPurposeRejected": wrongPurpose,
            "mismatchedRegistryIdentityRejected": mismatchedRegistryIdentity,
            "mismatchedExactGraphIdentityRejected": mismatchedExactGraphIdentity,
            "uniformOrderRejected": reversedUniforms,
            "dynamicSourceMismatchRejected": mismatchedDynamicSource,
            "authoredFallbackAccepted": authoredFallback?.exactIdentity.dynamicUniforms
                == [.init(
                    target: .effectConstant(
                        layerID: 1,
                        effectIndex: 2,
                        passIndex: 3,
                        name: "g_Gain"
                    ),
                    declaredSource: .timeline,
                    resolvedSource: .authored,
                    scriptAttachments: []
                )],
            "selectionProvenanceDiagnosticOnly": baseline.semanticIdentity
                    == provenanceVariant.semanticIdentity
                && baseline.exactIdentity == provenanceVariant.exactIdentity,
            "rawSamplerFlagsExactOnly": baseline.semanticIdentity
                    == authoredClampVariant.semanticIdentity
                && baseline.exactIdentity != authoredClampVariant.exactIdentity,
            "proceduralOpaqueWithoutSampledInputAccepted":
                proceduralOpaque?.textureSlots.allSatisfy({ $0 == nil }) == true
                && proceduralOpaque?.semanticIdentity.graphRole.bindings.isEmpty == true
                && colorIdentity(proceduralOpaque)?.framebufferInput == .opaque
                && colorIdentity(proceduralOpaque)?.fragmentOutput == .opaque,
            "unsupportedStateRejected": unsupportedState,
            "mismatchedGraphBindingRejected": mismatchedGraphBinding,
            "invalidGraphBindingSlotRejected": invalidGraphBindingSlot,
            "nonGraphWithGraphBindingRejected": nonGraphWithGraphBinding,
            "unresolvedPublicationRejected": unresolvedPublication,
            "unresolvedTransferRejected": unresolvedTransfer,
            "staleFrontendSchemaRejected": staleFrontendSchema,
            "straightPremultipliedAccepted": hasStraightAlphaBoundary(
                straightPremultiplied
            ),
            "straightOpaqueAccepted": hasStraightAlphaBoundary(straightOpaque),
            "straightInputRejected": straightInputRejected,
            "straightDataRejected": straightDataRejected,
            "scanlinePremultipliedLayerSourceAccepted":
                hasStraightAlphaPreservingBoundary(scanlinePremultiplied)
                && scanlinePremultiplied?.semanticIdentity.graphRole.effectInput
                    == .layerSource
                && scanlinePremultiplied?.semanticIdentity.graphRole.nodeTarget
                    == .effectOutput
                && colorIdentity(scanlinePremultiplied)?.framebufferInput
                    == .premultipliedAlpha,
            "scanlineDataLayerSourceRejected": scanlineDataRejected,
            "maskedDataAccepted": hasStraightAlphaBoundary(maskedDataAccepted),
            "maskedColorRejected": maskedColorRejected,
            "opaqueAlphaAccepted": hasStraightAlphaPreservingBoundary(
                opaqueAlphaAccepted
            ),
            "opaqueAlphaPremultipliedAccepted":
                hasStraightAlphaPreservingBoundary(opaqueAlphaPremultipliedAccepted),
            "wholeFilterAccepted": hasStraightAlphaUNormBoundary(
                wholeFilterAccepted
            ),
            "wholeFilterScalarFramebufferAccepted":
                wholeFilterScalarFramebufferAccepted?.outputContract
                    == .scalarRedUnorm,
            "wholeFilterScalarMismatchedBindingRejected":
                wholeFilterScalarMismatchedBindingRejected,
            "wholeFilterColorAuxiliaryRejected":
                wholeFilterColorAuxiliaryRejected,
            "wholeFilterEffectOutputRejected": wholeFilterEffectOutputRejected,
            "wholeFilterFramebufferRejected": wholeFilterFramebufferRejected,
            "ambiguousFramebufferRepresentationRejected":
                ambiguousFramebufferRepresentation,
            "independentSignalCompositeAccepted":
                compositingProjection?.framebufferInput == .premultipliedAlpha
                && compositingProjection?.fragmentOutput == .premultipliedAlpha,
            "independentSignalCompositeDataAuxiliaryAccepted":
                compositingDataAuxiliaryProjection?.framebufferInput
                    == .premultipliedAlpha
                && compositingDataAuxiliaryProjection?.fragmentOutput
                    == .premultipliedAlpha,
            "independentSignalCompositeColorAuxiliaryRejected":
                compositingColorAuxiliaryRejected,
            "independentSignalPreservingAccepted":
                preservingSignalProjection?.framebufferInput
                    == .independentAlphaSignal
                && preservingSignalProjection?.fragmentOutput
                    == .independentAlphaSignal,
            "independentSignalPreservingPremultipliedRejected":
                preservingPremultipliedRejected,
            "interpolatedSameRepresentationAccepted":
                interpolatedProjection?.framebufferInput == .premultipliedAlpha
                && interpolatedProjection?.fragmentOutput == .premultipliedAlpha,
            "interpolatedOpaquePremultipliedAccepted":
                interpolatedOpaquePremultipliedProjection?.framebufferInput
                    == .premultipliedAlpha
                && interpolatedOpaquePremultipliedProjection?.fragmentOutput
                    == .premultipliedAlpha,
            "interpolatedUnrelatedFramebufferIgnored":
                interpolatedWithUnrelatedFramebufferColor?
                    .fragmentOutput == .premultipliedAlpha,
            "interpolatedDataRejected": interpolatedDataRejected,
            "interpolatedIndependentSignalRejected":
                interpolatedIndependentSignalRejected,
            "interpolatedMismatchRejected": interpolatedMismatchRejected,
            "interpolatedUnsortedRejected": interpolatedUnsortedRejected,
            "associatedOverNamedOverlayAccepted":
                associatedOverNamedOverlayProjection?.framebufferInput
                    == .premultipliedAlpha
                && associatedOverNamedOverlayProjection?.fragmentOutput
                    == .premultipliedAlpha,
            "associatedOverColorOverlayWithoutFactRejected":
                associatedOverColorOverlayWithoutFactRejected,
            "associatedOverColorOverlayWrongSlotRejected":
                associatedOverColorOverlayWrongSlotRejected,
            "metalKeyDerived": baseline.metalCompileStateKey(
                attachmentPixelFormat: .bgra8Unorm,
                sampleCount: 1,
                device: device
            ) != nil,
            "invalidMetalKeyRejected": baseline.metalCompileStateKey(
                attachmentPixelFormat: .invalid,
                sampleCount: 0,
                device: device
            ) == nil,
        ]
        results.merge(scenePreparedAssemblyRegressionCases(baseline: baseline)) { _, new in new }
        let renamedShader = prepared(
            revision: "self-renamed-assembly-input",
            fragment: passthroughFragment.replacingOccurrences(of: "g_Gain", with: "u_RenamedGain")
                .replacingOccurrences(of: "uniformProbe", with: "renamedProbe")
        )
        let equivalentShader = prepared(
            revision: "self-equivalent-assembly-input",
            fragment: passthroughFragment.replacingOccurrences(
                of: "gl_FragColor = texSample2D(g_Texture0, v_TexCoord);",
                with: "vec4 sampled = texSample2D(g_Texture0, v_TexCoord); gl_FragColor = sampled;"
            )
        )
        for (label, shader) in [("renamed", renamedShader), ("equivalent", equivalentShader)] {
            guard let program = assemble(prepared: shader, textureSlots: slots(firstSlot)) else {
                results["prepared-\(label)-input-accepted"] = false
                continue
            }
            for (name, passed) in scenePreparedAssemblyRegressionCases(baseline: program) {
                results["\(label)-\(name)"] = passed
            }
        }
        let encoded = try JSONEncoder().encode(results)
        FileHandle.standardOutput.write(encoded)
    }
}
