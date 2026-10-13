// Complete preparation cases; state remains owned by the single fixture.
import Foundation
import Metal
import simd

func crossTemplateMaterialCacheTokens(_ device: MTLDevice) -> [String: String] {
    let shader = contract(revision: "material-cache-identity")
    let admitted = template(shader)
    guard case let .success(cache) = SceneResolvedMaterialVariantCache.launchValidated(
        template: admitted,
        maximumVariantCount: 8
    ), case .success = cache.precompileLaunchEnvelope(
        implicitFramebufferIdentity: graphTexture()
    ), case let .success(frame) = SceneResolvedMaterialFrameSnapshot.validated(
        textureSnapshot: snapshot(device),
        dynamicSnapshot: dynamicSnapshot(frameIndex: 1, source: nil),
        frameInputs: frameInputs(frameIndex: 1)
    ) else { return ["setup": "failed"] }
    let cases: [(String, Template)] = [
        ("equivalent", template(shader)),
        ("combos", template(shader, comboValues: ["CACHE_TEST": 1])),
        ("textures", template(shader, candidateCount: 2)),
        ("graphRole", template(shader, effectInputGraphTextureRole: .framebuffer)),
        ("renderState", template(shader, renderState: state(blending: "additive"))),
        ("inactiveCombos", template(shader, inheritedInactiveCombos: ["CACHE_TEST"])),
        ("ownerEligibility", template(shader, previousBlurredCompositeGenericOwnerEligible: true)),
        ("shaderContent", template(contract(
            revision: "material-cache-identity", arithmetic: true
        ))),
        ("sourceGraph", template(contract(
            revision: "material-cache-identity", includeSourceGraph: false
        ))),
        ("equivalentAfterRejection", template(shader)),
    ]
    return Dictionary(uniqueKeysWithValues: cases.map { name, candidate in
        let input = frame.finalizationInput(
            template: candidate,
            layerID: 9001,
            renderSize: CGSize(width: 640, height: 360),
            modelViewProjection: matrix_identity_float4x4,
            layerModelMatrix: layerModelMatrix,
            effectOutputModelViewProjection: effectOutputModelViewProjection,
            effectTextureProjectionMatrixInverse: effectProjectionInverse,
            implicitFramebufferIdentity: graphTexture()
        )
        switch cache.resolveSelection(input) {
        case .success: return (name, "success")
        case let .failure(failure):
            return (name, "\(failure.phase.rawValue)/\(failure.code.rawValue)")
        }
    })
}

func crossTemplateRuntimeLoopCacheToken(_ device: MTLDevice) -> String {
    let shader = contract(revision: "runtime-loop-cache-identity", runtimeLoop: true)
    let admitted = template(
        shader,
        uniformDeclarations: [staticDeclaration("Fractals", components: [5])]
    )
    let mismatched = template(
        shader,
        uniformDeclarations: [staticDeclaration("Fractals", components: [257])]
    )
    guard case let .success(cache) = SceneResolvedMaterialVariantCache.launchValidated(
        template: admitted,
        maximumVariantCount: 8
    ), case let .success(frame) = SceneResolvedMaterialFrameSnapshot.validated(
        textureSnapshot: snapshot(device, kind: .ready, frameIndex: 1),
        dynamicSnapshot: dynamicSnapshot(frameIndex: 1, source: nil),
        frameInputs: frameInputs(frameIndex: 1)
    ) else { return "setup-failed" }
    let input = frame.finalizationInput(
        template: mismatched,
                layerID: 9001,
                renderSize: CGSize(width: 640, height: 360),
        modelViewProjection: matrix_identity_float4x4,
        layerModelMatrix: layerModelMatrix,
        effectOutputModelViewProjection: effectOutputModelViewProjection,
        effectTextureProjectionMatrixInverse: effectProjectionInverse,
        implicitFramebufferIdentity: nil
    )
    return failureToken(
        SceneResolvedMaterialProgramFinalizer.finalize(
            input,
            variantCache: cache
        )
    )
}

func reachabilityIdentityMismatchToken(_ device: MTLDevice) -> String {
    let shader = contract(revision: "reachability-identity-mismatch")
    let admitted = template(shader)
    guard case let .success(cache) = SceneResolvedMaterialVariantCache.launchValidated(
        template: admitted,
        maximumVariantCount: 8
    ), case .success = cache.precompileLaunchEnvelope(
        implicitFramebufferIdentity: graphTexture()
    ), case let .success(frame) = SceneResolvedMaterialFrameSnapshot.validated(
        textureSnapshot: snapshot(device),
        dynamicSnapshot: dynamicSnapshot(frameIndex: 1, source: nil),
        frameInputs: frameInputs(frameIndex: 1)
    ) else { return "setup-failed" }
    let input = frame.finalizationInput(
        template: admitted,
                layerID: 9001,
                renderSize: CGSize(width: 640, height: 360),
        modelViewProjection: matrix_identity_float4x4,
        layerModelMatrix: layerModelMatrix,
        effectOutputModelViewProjection: effectOutputModelViewProjection,
        effectTextureProjectionMatrixInverse: effectProjectionInverse,
        implicitFramebufferIdentity: framebufferTexture()
    )
    return failureToken(
        SceneResolvedMaterialProgramFinalizer.finalize(input, variantCache: cache)
    )
}

func variantSelectionKeyMismatchTokens(
    _ device: MTLDevice
) -> [String: String] {
    let path = SceneVFSAssetPath("textures/variant-key-mismatch.tex")!
    let reference = Template.TextureReference.asset(path)
    let identity = SceneAssetTextureIdentity(
        path: path,
        purpose: .straightAlbedo
    )
    let shader = contract(
        revision: "variant-key-mismatch",
        samplerMetadata: #"{"material":"albedo","formatcombo":true}"#
    )
    let admitted = template(shader, primaryReference: reference)
    let runtimePublication = publication(
        device,
        requestIdentity: .asset(identity),
        purpose: .straightAlbedo,
        content: .color(.resolved(.straightAlpha)),
        authoredFormat: .dxt1
    )
    guard case let .success(cache) = SceneResolvedMaterialVariantCache.launchValidated(
        template: admitted,
        maximumVariantCount: 8,
        assetFormatFacts: [identity.reportToken: SceneShaderTextureFormat.rgba8888.macroValue]
    ), case .success = cache.precompileLaunchEnvelope(
        implicitFramebufferIdentity: nil,
        assetStates: [identity: .ready(runtimePublication.candidate.content)]
    ), case let .success(frame) = SceneResolvedMaterialFrameSnapshot.validated(
        textureSnapshot: snapshot(
            device,
            kind: .missing,
            additionalEntries: [
                .asset(identity): .ready(.init(
                    publication: runtimePublication,
                    resourceGeneration: 1
                )),
            ]
        ),
        dynamicSnapshot: dynamicSnapshot(frameIndex: 1, source: nil),
        frameInputs: frameInputs(frameIndex: 1)
    ) else { return ["failure": "setup-failed", "details": "setup-failed"] }
    let input = frame.finalizationInput(
        template: admitted,
                layerID: 9001,
                renderSize: CGSize(width: 640, height: 360),
        modelViewProjection: matrix_identity_float4x4,
        layerModelMatrix: layerModelMatrix,
        effectOutputModelViewProjection: effectOutputModelViewProjection,
        effectTextureProjectionMatrixInverse: effectProjectionInverse
    )
    let result = SceneResolvedMaterialProgramFinalizer.finalize(
        input,
        variantCache: cache
    )
    let details: String = switch result {
    case .success: "success"
    case let .failure(failure): failure.boundedDetails.joined(separator: ",")
    }
    return ["failure": failureToken(result), "details": details]
}

func resolverInvariantTokens(_ device: MTLDevice) -> [String: String] {
    let shader = contract(revision: "resolver-invariant-codes")
    let admitted = template(shader)
    guard case let .success(cache) = SceneResolvedMaterialVariantCache.launchValidated(
        template: admitted,
        maximumVariantCount: 8
    ), case .success = cache.precompileLaunchEnvelope(
        implicitFramebufferIdentity: nil
    ), case let .success(readyFrame) = SceneResolvedMaterialFrameSnapshot.validated(
        textureSnapshot: snapshot(device),
        dynamicSnapshot: dynamicSnapshot(frameIndex: 1, source: nil),
        frameInputs: frameInputs(frameIndex: 1)
    ) else { return ["setup": "failed"] }
    let readyInput = readyFrame.finalizationInput(
        template: admitted,
                layerID: 9001,
                renderSize: CGSize(width: 640, height: 360),
        modelViewProjection: matrix_identity_float4x4,
        layerModelMatrix: layerModelMatrix,
        effectOutputModelViewProjection: effectOutputModelViewProjection,
        effectTextureProjectionMatrixInverse: effectProjectionInverse
    )
    guard case let .success(selection) = cache.resolveSelection(readyInput),
          case let .success(absentFrame) = SceneResolvedMaterialFrameSnapshot.validated(
              textureSnapshot: snapshot(device, kind: .absent),
              dynamicSnapshot: dynamicSnapshot(frameIndex: 1, source: nil),
              frameInputs: frameInputs(frameIndex: 1)
          ) else { return ["setup": "failed"] }
    let absentInput = absentFrame.finalizationInput(
        template: admitted,
                layerID: 9001,
                renderSize: CGSize(width: 640, height: 360),
        modelViewProjection: matrix_identity_float4x4,
        layerModelMatrix: layerModelMatrix,
        effectOutputModelViewProjection: effectOutputModelViewProjection,
        effectTextureProjectionMatrixInverse: effectProjectionInverse
    )

    func token(_ body: () throws -> Void) -> String {
        do {
            try body()
            return "success"
        } catch let failure as SceneResolvedMaterialFailure {
            return "\(failure.phase.rawValue)/\(failure.code.rawValue)"
        } catch {
            return "untyped"
        }
    }

    return [
        "readiness": token {
            _ = try SceneResolvedMaterialTextureResolver.resolve(
                absentInput,
                variant: selection.variant,
                reachableSamplers: selection.reachableSamplers
            )
        },
        "variantKey": token {
            _ = try SceneResolvedMaterialTextureResolver.variantKey(
                readyInput,
                samplers: selection.variant.activeSamplers,
                reachableSamplers: selection.reachableSamplers,
                formatSlots: [8],
                allowPresenceIndependentDefaults: true
            )
        },
    ]
}

func unreachableGraphCandidateToken(_ device: MTLDevice) -> String {
    let inactive = framebufferTexture()
    return failureToken(finalize(
        shader: contract(revision: "unreachable-graph-candidate"),
        device: device,
        secondReference: .graph(inactive),
        additionalEntries: [
            .graph(inactive): readyStatus(
                device,
                identity: .graph(inactive),
                purpose: .premultipliedColor,
                content: .color(.resolved(.premultipliedAlpha))
            ),
        ]
    ))
}


final class SceneResolvedMaterialFinalizerPreparationCases {
    unowned let fixture: SceneResolvedMaterialFinalizerFixture

    init(_ fixture: SceneResolvedMaterialFinalizerFixture) {
        self.fixture = fixture
    }

    lazy var revisionA = finalize(
        shader: contract(revision: "revision-a"),
        device: self.fixture.device
    )

    lazy var revisionB = finalize(
        shader: contract(revision: "revision-b"),
        device: self.fixture.device
    )

    lazy var successfulPrograms: (Program, Program) = {
        guard case let .success(programA) = self.revisionA,
              case let .success(programB) = self.revisionB else {
            fatalError(
                "positive finalization failed: \(failureToken(self.revisionA)), "
                    + "\(failureToken(self.revisionB)); \(positiveDiagnostic(contract(revision: "debug")))"
            )
        }
        return (programA, programB)
    }()

    var programA: Program { successfulPrograms.0 }
    var programB: Program { successfulPrograms.1 }

    lazy var resolverInvariants = resolverInvariantTokens(self.fixture.device)

    lazy var variantSelectionKeyMismatch = variantSelectionKeyMismatchTokens(self.fixture.device)

    lazy var audioInputs = SceneAuthoredShaderAudioSpectrumInputs(
        left16: (0 ..< 16).map { Float($0 + 1) },
        right16: Array(repeating: 0, count: 16),
        left32: Array(repeating: 0, count: 32),
        right32: (0 ..< 32).map { Float(100 + $0) },
        left64: (0 ..< 64).map { Float(200 + $0) },
        right64: (0 ..< 64).map { Float(300 + $0) }
    )

    lazy var audioProgramResult = finalize(
        shader: contract(revision: "audio-spectrum", audioSpectrum: true),
        device: self.fixture.device,
        audioSpectrum: self.audioInputs
    )

    lazy var audioSpectrumEncoded: Bool = {
        guard case let .success(program) = self.audioProgramResult else {
            return false
        }
        guard let left16 = program.frontendProgram.uniformLayout.fields.first(
            where: { $0.name == "g_AudioSpectrum16Left" }
        ), let right32 = program.frontendProgram.uniformLayout.fields.first(
            where: { $0.name == "g_AudioSpectrum32Right" }
        ), let left64 = program.frontendProgram.uniformLayout.fields.first(
            where: { $0.name == "g_AudioSpectrum64Left" }
        ), let right64 = program.frontendProgram.uniformLayout.fields.first(
            where: { $0.name == "g_AudioSpectrum64Right" }
        ) else {
            return false
        }
        return left16.arrayCount == 16
            && right32.arrayCount == 32
            && left64.arrayCount == 64
            && right64.arrayCount == 64
            && Harness.float(program.uniformBytes, at: left16.offset + 3 * 4) == 4
            && Harness.float(program.uniformBytes, at: right32.offset + 5 * 4) == 105
            && Harness.float(program.uniformBytes, at: left64.offset + 7 * 4) == 207
            && Harness.float(program.uniformBytes, at: right64.offset + 9 * 4) == 309
    }()

    lazy var stageLocalProgram = finalize(
        shader: contract(
            revision: "stage-local-uniforms",
            stageLocalUniforms: true
        ),
        device: self.fixture.device
    )

    lazy var stageLocalUniformsEncoded: Bool = {
        guard case let .success(program) = self.stageLocalProgram,
              let vertex = program.frontendProgram.uniformLayout.fields.first(
                  where: { $0.name == "mwxV_g_Gain" }
              ),
              let fragment = program.frontendProgram.uniformLayout.fields.first(
                  where: { $0.name == "mwxF_g_Gain" }
              ) else {
            return false
        }
        return vertex.authoredName == "g_Gain"
            && fragment.authoredName == "g_Gain"
            && vertex.stage == .vertex
            && fragment.stage == .fragment
            && Harness.float(program.uniformBytes, at: vertex.offset) == 2
            && Harness.float(program.uniformBytes, at: fragment.offset) == 3
    }()

    lazy var sharedStageLocalProgram = finalize(
        shader: contract(
            revision: "shared-stage-local-binding",
            stageLocalUniforms: true,
            sharedStageLocalBinding: true
        ),
        device: self.fixture.device,
        uniformDeclarations: [directUserAlphaDeclaration()],
        dynamicSource: .userProperty,
        dynamicAlphaValue: .scalar(1.5),
        authoredAlphaValue: .scalar(0.75)
    )

    lazy var sharedStageLocalDynamicUniformsEncoded: Bool = {
        guard case let .success(program) = self.sharedStageLocalProgram,
              let vertex = program.frontendProgram.uniformLayout.fields.first(
                  where: { $0.name == "mwxV_g_Gain" }
              ),
              let fragment = program.frontendProgram.uniformLayout.fields.first(
                  where: { $0.name == "mwxF_g_Gain" }
              ) else {
            return false
        }
        return vertex.authoredName == "g_Gain"
            && fragment.authoredName == "g_Gain"
            && Harness.float(program.uniformBytes, at: vertex.offset) == 0.75
            && Harness.float(program.uniformBytes, at: fragment.offset) == 1.5
    }()

    lazy var exactCrossStageUniformCases: [String: Bool] = {
        let exactDeclaration = #"uniform float g_Gain; // {"material":"alpha","default":0.75,"range":[0,1]}"#
        let widerDeclaration = #"uniform float g_Gain; // {"material":"alpha","default":0.75,"range":[0,2]}"#
        let extraDeclaration = #"uniform float g_Extra; // {"material":"alpha","default":0.5,"range":[0,1]}"#
        func exact(
            _ contract: SceneShaderContract,
            stages: [SceneShaderContract.StageKind] = [.vertex, .fragment]
        ) -> [SceneResolvedMaterialShaderSchema.Uniform]? {
            guard let program = prepared(contract) else { return nil }
            return SceneResolvedMaterialShaderSchema.exactActiveUniforms(
                materialKey: "alpha",
                type: .float,
                stages: stages,
                prepared: program
            )
        }
        let good = exact(crossStageUniformContract(
            revision: "exact-cross-stage-good",
            vertexDeclarations: exactDeclaration,
            fragmentDeclarations: exactDeclaration
        ))
        let rangeMismatch = exact(crossStageUniformContract(
            revision: "exact-cross-stage-range-mismatch",
            vertexDeclarations: exactDeclaration,
            fragmentDeclarations: widerDeclaration
        ))
        return [
            "exactSet": good?.count == 2
                && good!.allSatisfy { $0.authoredRange == 0 ... 1 },
            "missingStage": exact(crossStageUniformContract(
                revision: "exact-cross-stage-missing",
                vertexDeclarations: "",
                fragmentDeclarations: exactDeclaration
            )) == nil,
            "extraConsumer": exact(crossStageUniformContract(
                revision: "exact-cross-stage-extra",
                vertexDeclarations: exactDeclaration,
                fragmentDeclarations: exactDeclaration + "\n" + extraDeclaration
            )) == nil,
            "sameStageDuplicate": exact(crossStageUniformContract(
                revision: "exact-cross-stage-duplicate",
                vertexDeclarations: exactDeclaration + "\n" + exactDeclaration,
                fragmentDeclarations: exactDeclaration
            )) == nil,
            "array": exact(crossStageUniformContract(
                revision: "exact-cross-stage-array",
                vertexDeclarations: #"uniform float g_Gain[2]; // {"material":"alpha","default":0.75,"range":[0,1]}"#,
                fragmentDeclarations: exactDeclaration
            )) == nil,
            "wrongType": exact(crossStageUniformContract(
                revision: "exact-cross-stage-wrong-type",
                vertexDeclarations: #"uniform vec2 g_Gain; // {"material":"alpha","default":"0.75 0.75","range":[0,1]}"#,
                fragmentDeclarations: exactDeclaration
            )) == nil,
            "rangeMismatchDetected": rangeMismatch?.count == 2
                && !rangeMismatch!.allSatisfy { $0.authoredRange == 0 ... 1 },
            "duplicateExpectedStage": exact(
                crossStageUniformContract(
                    revision: "exact-cross-stage-duplicate-expected",
                    vertexDeclarations: exactDeclaration,
                    fragmentDeclarations: exactDeclaration
                ),
                stages: [.vertex, .vertex]
            ) == nil,
        ]
    }()

    lazy var runtimeLoopProgram = finalize(
        shader: contract(
            revision: "runtime-loop-static-producer",
            runtimeLoop: true
        ),
        device: self.fixture.device,
        uniformDeclarations: [
            staticDeclaration("Fractals", components: [5]),
        ]
    )

    lazy var runtimeLoopStaticProducerAccepted: Bool = {
        guard case let .success(program) = self.runtimeLoopProgram,
              let field = program.frontendProgram.uniformLayout.fields.first(
                  where: { $0.name == "u_fractals" }
              ) else { return false }
        let compactSource = program.frontendProgram.metalSource.replacingOccurrences(
            of: " ",
            with: ""
        )
        return program.frontendProgram.staticLoopWork == 17
            && Harness.float(program.uniformBytes, at: field.offset) == 5
            && compactSource.contains("int(mwxUniforms.u_fractals)")
            && !compactSource.contains("clamp(mwxUniforms.u_fractals")
    }()

    lazy var pointerStateProgram = finalize(
        shader: contract(
            revision: "pointer-state-host-uniform",
            pointerState: true
        ),
        device: self.fixture.device,
        primaryButtonIsDown: true
    )

    lazy var pointerStateEncoded: Bool = {
        guard case let .success(program) = self.pointerStateProgram,
              let field = program.frontendProgram.uniformLayout.fields.first(
                  where: { $0.name == "g_PointerState" }
              ) else { return false }
        return field.type == .float4
            && Harness.float(program.uniformBytes, at: field.offset) == 0
            && Harness.float(program.uniformBytes, at: field.offset + 4) == 0
            && Harness.float(program.uniformBytes, at: field.offset + 8) == 1
            && Harness.float(program.uniformBytes, at: field.offset + 12) == 0
    }()

    lazy var admittedEffectIngress = admittedEffectIngressTokens(self.fixture.device)

    lazy var renderSizeField = self.programA.frontendProgram.uniformLayout.fields.first {
        $0.name == "mwxRenderSize"
    }!

    lazy var expectedRenderSize = SceneResolvedMaterialUniformEncoder.encodeHost(
        .renderSize,
        type: self.renderSizeField.type,
        inputs: uniformInputs(),
        slots: self.programA.textureSlots
    )!

    lazy var encodedRange = self.renderSizeField.offset
        ..< self.renderSizeField.offset + self.renderSizeField.type.byteSize

    lazy var uniformLayoutCorrect = self.programA.uniformBytes.count
            == self.programA.frontendProgram.uniformLayout.byteSize
        && !self.programA.uniformBytes.isEmpty
        && self.programA.uniformBytes.subdata(in: self.encodedRange) == self.expectedRenderSize

    lazy var effectProjectionField = self.programA.frontendProgram.uniformLayout.fields.first {
        $0.name == "g_EffectTextureProjectionMatrixInverse"
    }!

    lazy var effectProjectionEncoded = [0, 5, 10, 15].enumerated().allSatisfy {
        index, component in
        Harness.float(self.programA.uniformBytes, at: self.effectProjectionField.offset + component * 4)
            == Float(index + 2)
    }

    lazy var modelViewProjectionInverseField =
        self.programA.frontendProgram.uniformLayout.fields.first {
            $0.name == "g_ModelViewProjectionMatrixInverse"
        }!

    lazy var modelViewProjectionInverseEncoded = [0, 5, 10, 15].allSatisfy {
        Harness.float(
            self.programA.uniformBytes,
            at: self.modelViewProjectionInverseField.offset + $0 * 4
        ) == 1
    }

    lazy var layerModelField = self.programA.frontendProgram.uniformLayout.fields.first {
        $0.name == "g_LayerModelMatrix"
    }!

    lazy var layerModelEncoded = [0, 5, 10, 15].enumerated().allSatisfy {
        index, component in
        Harness.float(self.programA.uniformBytes, at: self.layerModelField.offset + component * 4)
            == Float(index + 6)
    }

    lazy var forwardProjectionField = self.programA.frontendProgram.uniformLayout.fields.first {
        $0.name == "g_EffectTextureProjectionMatrix"
    }!

    lazy var effectModelViewProjectionField =
        self.programA.frontendProgram.uniformLayout.fields.first {
            $0.name == "g_EffectModelViewProjectionMatrix"
        }!

    lazy var expectedForwardDiagonal: [Float] = [0.5, 1.0 / 3.0, 0.25, 0.2]

    lazy var forwardProjectionEncoded = [0, 5, 10, 15].enumerated().allSatisfy {
        index, component in
        abs(Harness.float(
            self.programA.uniformBytes,
            at: self.forwardProjectionField.offset + component * 4
        ) - self.expectedForwardDiagonal[index]) < 0.000_001
    }

    lazy var effectModelViewProjectionEncoded =
        [0, 5, 10, 15].enumerated().allSatisfy { index, component in
            let outputDiagonal: [Float] = [7, 11, 13, 17]
            let targetScale: Float = switch component {
            case 0: 1 / 640
            case 5: 1 / 360
            default: 1
            }
            return abs(Harness.float(
                self.programA.uniformBytes,
                at: self.effectModelViewProjectionField.offset + component * 4
            ) - outputDiagonal[index] * targetScale) < 0.000_001
        }

    lazy var parallaxField = self.programA.frontendProgram.uniformLayout.fields.first {
        $0.name == "g_ParallaxPosition"
    }!

    lazy var parallaxPositionEncoded =
        Harness.float(self.programA.uniformBytes, at: self.parallaxField.offset) == 0.75
        && Harness.float(self.programA.uniformBytes, at: self.parallaxField.offset + 4) == 0.375

    lazy var parallaxRangePreserved = [SIMD2<Float>.zero, SIMD2(2, -2)].allSatisfy { value in
        guard let bytes = SceneResolvedMaterialUniformEncoder.encodeHost(
            .parallaxPosition, type: .float2,
            inputs: uniformInputs(parallax: value), slots: []
        ) else { return false }
        return Harness.float(bytes, at: 0) == 0.5 + value.x * 0.5
            && Harness.float(bytes, at: 4) == 0.5 + value.y * 0.5
    }

    lazy var invalidParallaxRejected = SceneResolvedMaterialUniformEncoder.encodeHost(
        .parallaxPosition, type: .float2,
        inputs: uniformInputs(parallax: SIMD2(.nan, 0)), slots: []
    ) == nil

}
