// Complete failures cases; state remains owned by the single fixture.
import Foundation
import Metal
import simd


final class SceneResolvedMaterialFinalizerFailureCases {
    unowned let fixture: SceneResolvedMaterialFinalizerFixture

    init(_ fixture: SceneResolvedMaterialFinalizerFixture) {
        self.fixture = fixture
    }

    lazy var arithmeticOutputProgram = finalize(
        shader: contract(revision: "arithmetic-output", arithmetic: true),
        device: fixture.device
    )

    var arithmeticColorBoundary: [String: Bool] {
        guard case let .success(program) = arithmeticOutputProgram,
              let boundary = program.frontendProgram.colorBoundary else {
            return ["acceptedWithOrdinaryBoundary": false]
        }
        var mask: UInt32 = 1
        let expectedMask = withUnsafeBytes(of: &mask) { Data($0) }
        return [
            "acceptedWithOrdinaryBoundary": true,
            "actualPMAInputRetained": program.textureSlots[0]?.resource.publication
                .candidate.content == .color(.resolved(.premultipliedAlpha)),
            "colorSlotNormalizedOnce": boundary.colorInputSlots == [0]
                && boundary.alphaInputSlots.isEmpty && boundary.signalPassthroughSlot == nil,
            "actualInputMaskEncoded": program.resolvedUniforms.contains {
                if case .host(.premultipliedColorInputMask) = $0.source {
                    return $0.encodedValue == expectedMask
                }
                return false
            },
            "authoredMathUsesStraightColorDomain": boundary.outputRepresentation == .straightAlpha
                && program.semanticIdentity.outputContract == .color(.init(
                    framebufferInput: .straightAlpha, fragmentOutput: .straightAlpha
                )),
        ]
    }

    lazy var failures: [String: String] = [
        "nonFramebufferDoesNotInject": failureToken(finalize(
            shader: contract(
                revision: "non-framebuffer-no-injection",
                samplerMetadata: #"{"material":"source"}"#
            ),
            device: self.fixture.device,
            includePrimaryCandidate: false,
            implicitFramebufferIdentity: graphTexture()
        )),
        "framebufferWithoutIdentity": failureToken(finalize(
            shader: contract(
                revision: "framebuffer-without-identity",
                samplerMetadata: #"{"material":"framebuffer"}"#
            ),
            device: self.fixture.device,
            includePrimaryCandidate: false
        )),
        "previousWithoutIdentity": failureToken(finalize(
            shader: contract(
                revision: "previous-without-identity",
                samplerMetadata: #"{"material":"previous"}"#
            ),
            device: self.fixture.device,
            includePrimaryCandidate: false
        )),
        "historicalFramebufferWithoutHidden": failureToken(finalize(
            shader: contract(
                revision: "historical-framebuffer-without-hidden",
                samplerMetadata:
                    #"{"material":"ui_editor_properties_framebuffer"}"#
            ),
            device: self.fixture.device,
            includePrimaryCandidate: false,
            implicitFramebufferIdentity: graphTexture()
        )),
        "historicalFramebufferLabelOnly": failureToken(finalize(
            shader: contract(
                revision: "historical-framebuffer-label-only",
                samplerMetadata:
                    #"{"material":"source","label":"ui_editor_properties_framebuffer","hidden":true}"#
            ),
            device: self.fixture.device,
            includePrimaryCandidate: false,
            implicitFramebufferIdentity: graphTexture()
        )),
        "unknownEditorMaterialAlias": failureToken(finalize(
            shader: contract(
                revision: "unknown-editor-material-alias",
                samplerMetadata:
                    #"{"material":"ui_editor_properties_source","hidden":true}"#
            ),
            device: self.fixture.device,
            includePrimaryCandidate: false,
            implicitFramebufferIdentity: graphTexture()
        )),
        "regularGraphSampler": failureToken(finalize(
            shader: contract(revision: "regular-graph-sampler"),
            device: self.fixture.device
        )),
        "customPurposeIgnored": failureToken(finalize(
            shader: contract(
                revision: "custom-purpose",
                samplerMetadata: #"{"purpose":"mask"}"#
            ),
            device: self.fixture.device
        )),
        "unknownMode": failureToken(finalize(
            shader: contract(
                revision: "unknown-mode",
                samplerMetadata: #"{"mode":"mystery"}"#
            ),
            device: self.fixture.device
        )),
        "authoredOverridesShaderDefault": failureToken(finalize(
            shader: contract(
                revision: "authored-overrides-default",
                samplerMetadata: #"{"default":"textures/fallback.tex"}"#
            ),
            device: self.fixture.device
        )),
        "authoredFailureDoesNotUseShaderDefault": failureToken(finalize(
            shader: contract(
                revision: "authored-failure-no-default",
                samplerMetadata: #"{"default":"textures/fallback.tex"}"#
            ),
            device: self.fixture.device,
            snapshotKind: .unavailable
        )),
        "missingUniformDefault": failureToken(finalize(
            shader: contract(
                revision: "missing-uniform-default",
                uniformMetadata: nil
            ),
            device: self.fixture.device
        )),
        "malformedUniformDefault": failureToken(finalize(
            shader: contract(
                revision: "malformed-uniform-default",
                uniformMetadata: #"{"material":"Tint","default":"1 nope 0"}"#
            ),
            device: self.fixture.device
        )),
        "exactWhitespaceUniformBindingKey": failureToken(finalize(
            shader: contract(
                revision: "exact-whitespace-uniform-binding-key",
                uniformMetadata:
                    #"{"material":"Anti-alias blurring ","default":"1 0.5 0.25"}"#
            ),
            device: self.fixture.device,
            uniformDeclarations: [
                staticDeclaration(
                    "Anti-alias blurring ",
                    components: [0.2, 0.3, 0.4]
                ),
            ]
        )),
        "malformedStaticDeclaration": failureToken(finalize(
            shader: contract(revision: "malformed-static-declaration"),
            device: self.fixture.device,
            uniformDeclarations: [
                staticDeclaration("Tint", components: [1]),
            ]
        )),
        "uniformDeclarationConflict": failureToken(finalize(
            shader: contract(revision: "uniform-declaration-conflict"),
            device: self.fixture.device,
            uniformDeclarations: [
                staticDeclaration("Tint", components: [1, 0, 0]),
                staticDeclaration("u_Tint", components: [0, 1, 0]),
            ]
        )),
        "hostUniformDeclarationConflict": failureToken(finalize(
            shader: contract(revision: "host-uniform-declaration-conflict"),
            device: self.fixture.device,
            uniformDeclarations: [
                staticDeclaration("g_Time", components: [99]),
            ]
        )),
        "hostUniformBindingInvalid": failureToken(finalize(
            shader: contract(revision: "host-uniform-binding-invalid"),
            device: self.fixture.device,
            resolvedLayerModelMatrix: simd_float4x4(
                diagonal: SIMD4(.nan, 1, 1, 1)
            )
        )),
        "provenTimelineScriptValue": failureToken(finalize(
            shader: contract(revision: "timeline-script-value"),
            device: self.fixture.device,
            uniformDeclarations: [dynamicDeclaration([.sceneScript])],
            dynamicSource: .sceneScript
        )),
        "unknownTimelineScriptAttachment": failureToken(finalize(
            shader: contract(revision: "unknown-timeline-script-attachment"),
            device: self.fixture.device,
            uniformDeclarations: [dynamicDeclaration(
                [.timeline],
                attachments: [.unproven]
            )],
            dynamicSource: .timeline
        )),
        "authoredDynamicFallback": failureToken(finalize(
            shader: contract(revision: "authored-dynamic-fallback"),
            device: self.fixture.device,
            uniformDeclarations: [dynamicDeclaration([.timeline])],
            dynamicSource: .authored
        )),
        "dynamicSourceMismatch": failureToken(finalize(
            shader: contract(revision: "dynamic-source-mismatch"),
            device: self.fixture.device,
            uniformDeclarations: [dynamicDeclaration([.timeline])],
            dynamicSource: .userProperty
        )),
        "multipleValueContributors": failureToken(finalize(
            shader: contract(revision: "multiple-value-contributors"),
            device: self.fixture.device,
            uniformDeclarations: [dynamicDeclaration([
                .userProperty("first"), .userProperty("second"),
            ])]
        )),
        "runtimeLoopMetadataOnly": failureToken(finalize(
            shader: contract(
                revision: "runtime-loop-metadata-only",
                runtimeLoop: true,
                runtimeLoopEditorHints: true
            ),
            device: self.fixture.device
        )),
        "runtimeLoopDynamicProducer": failureToken(finalize(
            shader: contract(
                revision: "runtime-loop-dynamic-producer",
                runtimeLoop: true
            ),
            device: self.fixture.device,
            uniformDeclarations: [dynamicScalarDeclaration("Fractals")]
        )),
        "runtimeLoopOverBudget": failureToken(finalize(
            shader: contract(
                revision: "runtime-loop-over-budget",
                runtimeLoop: true
            ),
            device: self.fixture.device,
            uniformDeclarations: [
                staticDeclaration("Fractals", components: [257]),
            ]
        )),
        "runtimeLoopNegativeExact": failureToken(finalize(
            shader: contract(revision: "runtime-loop-negative", runtimeLoop: true),
            device: self.fixture.device,
            uniformDeclarations: [staticDeclaration("Fractals", components: [-1])]
        )),
        "runtimeLoopNonIntegralExact": failureToken(finalize(
            shader: contract(revision: "runtime-loop-non-integral", runtimeLoop: true),
            device: self.fixture.device,
            uniformDeclarations: [staticDeclaration("Fractals", components: [5.5])]
        )),
        "runtimeLoopNonFiniteExact": failureToken(finalize(
            shader: contract(revision: "runtime-loop-non-finite", runtimeLoop: true),
            device: self.fixture.device,
            uniformDeclarations: [staticDeclaration("Fractals", components: [.nan])]
        )),
        "runtimeLoopMultipleProducer": failureToken(finalize(
            shader: contract(revision: "runtime-loop-multiple", runtimeLoop: true),
            device: self.fixture.device,
            uniformDeclarations: [
                staticDeclaration("Fractals", components: [5]),
                staticDeclaration("u_fractals", components: [5]),
            ]
        )),
        "runtimeLoopCrossTemplateCache":
            crossTemplateRuntimeLoopCacheToken(self.fixture.device),
        "variantSelectionReachabilityIdentity":
            reachabilityIdentityMismatchToken(self.fixture.device),
        "variantSelectionKey":
            self.fixture.preparation.variantSelectionKeyMismatch["failure"] ?? "missing",
        "variantSelectionKeyDetails":
            self.fixture.preparation.variantSelectionKeyMismatch["details"] ?? "missing",
        "terminalGraphOverrideUnavailable":
            self.fixture.preparation.resolverInvariants["readiness"] ?? "missing",
        "textureVariantKeyIdentityInvariant":
            self.fixture.preparation.resolverInvariants["variantKey"] ?? "missing",
        "multipleCandidates": failureToken(finalize(
            shader: contract(revision: "multiple-candidates"),
            device: self.fixture.device,
            candidateCount: 2
        )),
        "unreachableGraphCandidate": unreachableGraphCandidateToken(self.fixture.device),
        "providerUnavailableDoesNotUseEarlierCandidate": failureToken(
            self.fixture.providers.providerUnavailableDoesNotFallback
        ),
        "providerAbsentUsesEarlierCandidate": failureToken(self.fixture.providers.providerAbsentFallback),
        "providerMissingDoesNotUseEarlierCandidate": failureToken(
            self.fixture.providers.providerMissingDoesNotFallback
        ),
        "providerPendingDoesNotUseEarlierCandidate": failureToken(
            self.fixture.providers.providerPendingDoesNotFallback
        ),
        "systemProviderPendingVisualFallback": visualFallbackToken(
            self.fixture.providers.providerPending
        ),
        "providerUnavailableDoesNotUseShaderDefault": failureToken(
            self.fixture.providers.shaderDefaultAfterUnavailableProvider
        ),
        "providerAbsentUsesShaderDefault": failureToken(
            self.fixture.providers.shaderDefaultAfterAbsentProvider
        ),
        "missingGraphIdentity": failureToken(finalize(
            shader: contract(revision: "missing-graph-identity"),
            device: self.fixture.device,
            snapshotKind: .missing
        )),
        "textureDynamicFrameMismatch": failureToken(finalize(
            shader: contract(revision: "texture-dynamic-frame-mismatch"),
            device: self.fixture.device,
            textureFrameIndex: 2
        )),
        "dynamicInputsFrameMismatch": failureToken(finalize(
            shader: contract(revision: "dynamic-inputs-frame-mismatch"),
            device: self.fixture.device,
            frameInputIndex: 2
        )),
        "pending": failureToken(finalize(
            shader: contract(revision: "pending"),
            device: self.fixture.device,
            snapshotKind: .pending
        )),
        "unavailable": failureToken(finalize(
            shader: contract(revision: "unavailable"),
            device: self.fixture.device,
            snapshotKind: .unavailable
        )),
        "incompletePublication": failureToken(finalize(
            shader: contract(revision: "incomplete-publication"),
            device: self.fixture.device,
            snapshotKind: .incomplete
        )),
        "straightGraphColor": failureToken(finalize(
            shader: contract(revision: "straight-graph-color"),
            device: self.fixture.device,
            snapshotKind: .straightGraphColor
        )),
        "purposeMismatch": failureToken(finalize(
            shader: contract(revision: "purpose-mismatch"),
            device: self.fixture.device,
            snapshotKind: .purposeMismatch
        )),
        "unsupportedSampler": failureToken(finalize(
            shader: contract(revision: "unsupported-sampler"),
            device: self.fixture.device,
            snapshotKind: .unsupportedSampler
        )),
        "slotSchemaMismatch": failureToken(finalize(
            shader: contract(revision: "slot-schema-mismatch"),
            device: self.fixture.device,
            slot: 1
        )),
        "unsupportedState": failureToken(finalize(
            shader: contract(revision: "unsupported-state"),
            device: self.fixture.device,
            renderState: state(blending: "translucent")
        )),
        "unresolvedPublication": failureToken(finalize(
            shader: contract(revision: "unresolved-publication"),
            device: self.fixture.device,
            snapshotKind: .unresolvedColor
        )),
        "dataGraphInput": failureToken(finalize(
            shader: contract(revision: "data-input"),
            device: self.fixture.device,
            snapshotKind: .data
        )),
        "arithmeticOutput": failureToken(arithmeticOutputProgram),
        "arithmeticScalarOutput": failureToken(finalize(
            shader: contract(revision: "arithmetic-scalar-output", arithmetic: true),
            device: self.fixture.device,
            outputStorage: .scalarRedUnorm
        )),
        "scalarRedConsumer": failureToken(self.fixture.framebuffer.scalarRedConsumerProgram),
        "rgbaDataConsumer": failureToken(self.fixture.framebuffer.rgbaDataConsumerProgram),
        "scalarRedForgedTEXFormat": failureToken(self.fixture.framebuffer.scalarRedForgedTEXFormat),
        "scalarRedWrongFormat": failureToken(self.fixture.framebuffer.scalarRedWrongFormat),
        "graphRoleIdentityInvariant": failureToken(self.fixture.framebuffer.graphRoleIdentityFailure),
        "programAssemblyIdentityInvariant": failureToken(
            self.fixture.framebuffer.programAssemblyIdentityFailure
        ),
        "maskedMissing": failureToken(self.fixture.providers.maskedMissing),
        "maskedPending": failureToken(self.fixture.providers.maskedPending),
        "maskedWrongPurpose": failureToken(self.fixture.providers.maskedWrongPurpose),
        "maskedColorAuxiliary": failureToken(self.fixture.providers.maskedColorAuxiliary),
        "overlayColorAuxiliary": failureToken(self.fixture.providers.overlayColorAuxiliary),
        "optionalUntypedMask": failureToken(self.fixture.providers.optionalUntypedMask),
        "optionalMaskPendingDoesNotUseDefault": failureToken(
            self.fixture.providers.optionalMaskPending
        ),
        "optionalMaskWrongPurposeDoesNotUseDefault": failureToken(
            self.fixture.providers.optionalMaskWrongPurpose
        ),
        "activeDefaultMaskMissing": failureToken(self.fixture.providers.activeDefaultMaskMissing),
        "timelineVectorTypeMismatch": failureToken(self.fixture.uniforms.timelineVectorTypeMismatch),
        "unequalScalarSplatFallback": failureToken(
            self.fixture.uniforms.unequalScalarSplatFallback
        ),
        "nonUserScalarSplatContributor": failureToken(
            self.fixture.uniforms.nonUserScalarSplatContributor
        ),
        "extraKeyScalarSplat": failureToken(self.fixture.uniforms.extraKeyScalarSplat),
        "scriptKeyScalarSplat": failureToken(self.fixture.uniforms.scriptKeyScalarSplat),
        "unequalDefaultStaticScalarSplat": failureToken(
            self.fixture.uniforms.unequalDefaultStaticScalarSplat
        ),
        "missingDefaultStaticScalarSplat": failureToken(
            self.fixture.uniforms.missingDefaultStaticScalarSplat
        ),
        "nonFiniteDefaultStaticScalarSplat": failureToken(
            self.fixture.uniforms.nonFiniteDefaultStaticScalarSplat
        ),
        "wrongABIStaticScalarSplat": failureToken(
            self.fixture.uniforms.wrongABIStaticScalarSplat
        ),
        "arrayStaticScalarSplat": failureToken(
            self.fixture.uniforms.arrayStaticScalarSplat
        ),
        "nonFiniteStaticScalarSplat": failureToken(
            self.fixture.uniforms.nonFiniteStaticScalarSplat
        ),
        "unprovenStaticScalarSplat": failureToken(
            self.fixture.uniforms.unprovenStaticScalarSplat
        ),
        "scalarShaderDefaultOnly": failureToken(
            self.fixture.uniforms.scalarShaderDefaultOnly
        ),
    ]

}
