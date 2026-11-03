import Metal

// Compiled with the finalizer fixtures in the same self-test module. Its input
// builders are self-authored and cover prepared bindings plus serial frames.
func scenePreparedVariantFrameCases(_ device: MTLDevice) -> [String: Bool] {
    let shader = contract(revision: "prepared-variant-serial-frames")
    let declarations = [dynamicDeclaration([.timeline])]
    let admitted = template(shader, uniformDeclarations: declarations)
    guard case let .success(cache) = SceneResolvedMaterialVariantCache.launchValidated(
        template: admitted, textureFormatSlots: SceneResolvedMaterialShaderSchema.textureFormatSlots(in: admitted), maximumVariantCount: 16
    ), case .success = cache.precompileLaunchEnvelope(implicitFramebufferIdentity: nil),
       let variant = cache.launchEnvelopeCapabilitySnapshot().variants.first else {
        return ["preparedVariantFixtureReady": false]
    }
    let initialCounters = cache.counters
    var frames: [Program] = []
    for index in 1 ... 60 {
        let result = finalize(
            shader: shader, device: device,
            uniformDeclarations: declarations,
            textureFrameIndex: UInt64(index),
            dynamicFrameIndex: UInt64(index), frameInputIndex: UInt64(index),
            dynamicSource: .timeline,
            dynamicTintValue: .vector3(Double(index) / 100, 0.5, 0.25),
            variantCache: cache
        )
        guard case let .success(program) = result else {
            return ["preparedVariantSerialFramesReady": false]
        }
        frames.append(program)
    }
    let failed = finalize(
        shader: shader, device: device, uniformDeclarations: declarations,
        snapshotKind: .incomplete, dynamicSource: .timeline,
        variantCache: cache
    )
    let recovered = finalize(
        shader: shader, device: device, uniformDeclarations: declarations,
        textureFrameIndex: 61, dynamicFrameIndex: 61, frameInputIndex: 61,
        dynamicSource: .timeline, dynamicTintValue: .vector3(0.61, 0.5, 0.25),
        variantCache: cache
    )
    let finalCounters = cache.counters
    guard case let .success(current) = recovered,
          let first = frames.first, let last = frames.last else {
        return ["preparedVariantFailureRecoveryReady": false]
    }
    var cases: [String: Bool] = [
        "serialFrameShaderAndPreparedIdentityUseAdmittedVariant": frames.allSatisfy {
            $0.semanticIdentity.shader == variant.preparedAssembly.shaderIdentity
                && $0.semanticIdentity.renderState == variant.preparedAssembly.renderStateIdentity
                && $0.exactIdentity.prepared == variant.preparedAssembly.preparedIdentity
        },
        "serialFramesResolveCurrentUniformBytes": first.uniformBytes != last.uniformBytes
            && last.uniformBytes != current.uniformBytes,
        "serialFramesResolveCurrentTextureObjects": first.exactIdentity.textureSlots
            != last.exactIdentity.textureSlots,
        "serialFramesDoNotPrepareOrCompileAgain": initialCounters.shaderPreparationCount
            == finalCounters.shaderPreparationCount
            && initialCounters.frontendCompilationCount == finalCounters.frontendCompilationCount,
        "incompletePublicationDoesNotReusePreviousProgram": failureToken(failed) != "success",
        "failedFrameDoesNotInvalidateAdmittedVariant": current.semanticIdentity.shader
            == variant.preparedAssembly.shaderIdentity,
    ]
    cases.merge(scenePreparedVariantAdmissionCases(template: admitted, variant: variant)) { _, new in new }
    return cases
}

/// Prepared sampler projection and individual failures use the real admission owner.
private func scenePreparedVariantAdmissionCases(
    template value: SceneResolvedMaterialTemplate,
    variant: SceneResolvedMaterialCompiledVariant
) -> [String: Bool] {
    typealias Frontend = SceneAuthoredShaderProgram
    let frontend = variant.frontendProgram
    let prepared = variant.preparedShader
    let vertex = prepared.vertex
    let stale = SceneShaderPreparedProgram(vertex: .init(
        frontendSchemaVersion: 0, sourceDialect: vertex.sourceDialect,
        backend: vertex.backend, compatibilityTarget: vertex.compatibilityTarget,
        stage: vertex.stage, rootRelativePath: vertex.rootRelativePath,
        source: vertex.source, sourceMap: vertex.sourceMap,
        activeAnnotations: vertex.activeAnnotations, activeDeclarations: vertex.activeDeclarations,
        compatibilityMacroDependencies: vertex.compatibilityMacroDependencies,
        dependencies: vertex.dependencies, dependencySHA256: vertex.dependencySHA256,
        moduleDependencies: vertex.moduleDependencies, moduleDependencySHA256: vertex.moduleDependencySHA256,
        variantSHA256: vertex.variantSHA256, preparedSHA256: vertex.preparedSHA256
    ), fragment: prepared.fragment, colorContract: prepared.colorContract, cacheKey: prepared.cacheKey)
    let field = frontend.uniformLayout.fields[0]
    let invalidLayout = SceneAuthoredShaderUniformLayout(
        fields: [.init(name: field.name, type: field.type, offset: 1)],
        byteSize: frontend.uniformLayout.byteSize
    )
    func changed(layout: SceneAuthoredShaderUniformLayout? = nil,
                 mismatchedBinding: Bool = false,
                 zeroPaddedBinding: Bool = false) -> Frontend {
        .init(
            metalSource: frontend.metalSource,
            vertexFunctionName: frontend.vertexFunctionName,
            fragmentFunctionName: frontend.fragmentFunctionName,
            uniformBufferIndex: frontend.uniformBufferIndex,
            uniformLayout: layout ?? frontend.uniformLayout,
            textureBindings: frontend.textureBindings.map {
                .init(name: mismatchedBinding ? "selfFixtureWrongSampler"
                        : zeroPaddedBinding ? "g_Texture0\($0.slot)" : $0.name,
                      slot: $0.slot, channelUse: $0.channelUse)
            },
            staticLoopWork: frontend.staticLoopWork, colorTransfer: frontend.colorTransfer,
            fragmentOutputChannelUse: frontend.fragmentOutputChannelUse,
            backend: frontend.backend, vertexPositionInput: frontend.vertexPositionInput,
            colorBoundary: frontend.colorBoundary
        )
    }
    let key = SceneResolvedMaterialVariantKey(
        readinessMask: variant.readinessMask, textureFormats: variant.textureFormats
    )!
    func token(_ candidate: Frontend, shader: SceneShaderPreparedProgram,
               missingSampler: Bool = false, includeDetails: Bool = false,
               sourceSamplers: [Int: SceneResolvedMaterialShaderSchema.Sampler]? = nil,
               candidateTemplate: SceneResolvedMaterialTemplate? = nil,
               observeProjection: Bool = false) -> String {
        let template = candidateTemplate ?? value
        let samplers = missingSampler ? [:] : sourceSamplers ?? variant.activeSamplers
        let input = observeProjection ? graphTexture() : nil
        let facts = observeProjection ? SceneResolvedMaterialShaderSchema.graphInputSourceSlotFacts(
            template: template, samplers: samplers, inputIdentity: input,
            sourceColorTransfer: candidate.colorTransfer
        ) : variant.graphInputSourceSlotFacts
        do {
            let finalized = try SceneResolvedMaterialVariantCache.finalizeVariantBindings(
                template: template, variantKey: key, prepared: shader,
                compilerSources: .init(vertex: shader.vertex.source, fragment: shader.fragment.source),
                routeDecision: variant.routeDecision, compatibilityTargetAdmissionPending: true,
                frontend: candidate, boundedOutput: nil, artifactFailure: [],
                sourceActiveSamplers: samplers,
                implicitFramebufferIdentity: input,
                sourceGraphInputFacts: facts,
                neutralTextureResolution: variant.neutralTextureResolution,
                runtimeLoopBounds: variant.runtimeLoopBounds,
                conditionalGeneratedRGBInputContract: variant.conditionalGeneratedRGBInputContract,
                premultipliedColorInputSlots: variant.premultipliedColorInputSlots
            )
            if observeProjection {
                return "samplers:\(finalized.samplers.keys.sorted())|facts:\(finalized.graphInputFacts.keys.sorted())"
            }
            return "success"
        } catch let failure as SceneResolvedMaterialFailure {
            let token = "\(failure.phase.rawValue)/\(failure.code.rawValue)"
            return includeDetails ? token + "|" + failure.boundedDetails.joined(separator: "|") : token
        } catch { return "untyped" }
    }
    let frontendFailure = "frontend/shaderFrontendFailed"
    let samplerFailure = "invariant/samplerBindingIdentityMismatch"
    var cases: [String: Bool] = [
        "invalidLayoutRejectedAtPreparationFactory": token(changed(layout: invalidLayout),
            shader: prepared) == frontendFailure,
        "staleSchemaRejectedAtPreparationFactory": token(frontend, shader: stale) == frontendFailure,
        "validABIStillReportsMissingSampler": token(frontend, shader: prepared,
            missingSampler: true) == samplerFailure,
        "validABIStillReportsMismatchedSampler": token(changed(mismatchedBinding: true),
            shader: prepared) == samplerFailure,
        "validABIRejectsZeroPaddedSampler": token(changed(zeroPaddedBinding: true),
            shader: prepared) == samplerFailure,
        "missingSamplerPrecedesPreparedNameFailure": token(changed(zeroPaddedBinding: true),
            shader: prepared, missingSampler: true, includeDetails: true)
            .hasPrefix(samplerFailure + "|sampler-missing|"),
        "typedFailureThenOriginalAdmissionRecovers": token(frontend, shader: prepared) == "success",
    ]
    let liveShader = contract(
        revision: "prepared-live-second-sampler", uniformMetadata: nil, semanticProbes: false,
        fragmentSourceOverride: """
        varying vec2 v_TexCoord;
        uniform sampler2D g_Texture0; // {"material":"framebuffer","hidden":true}
        uniform sampler2D g_Texture2; // {"material":"framebuffer","hidden":true}
        void main() {
            vec4 first = texSample2D(g_Texture0, v_TexCoord);
            vec4 second = texSample2D(g_Texture2, v_TexCoord);
            gl_FragColor = mix(first, second, 0.5);
        }
        """
    )
    guard case let .accepted(livePrepared) = SceneAuthoredShaderPreparation.prepareShaderStages(
        contract: liveShader, combos: [:], inactiveComboProviders: [], textureReadiness: [:]
    ), let liveFrontend = SceneAuthoredShaderFrontend.compile(
        vertexSource: livePrepared.vertex.source, fragmentSource: livePrepared.fragment.source
    ).program, let sourceSamplers = try? SceneResolvedMaterialShaderSchema.activeSamplers(livePrepared)
    else { cases["samplerProjectionFixtureReady"] = false; return cases }
    let liveTemplate = template(liveShader)
    let sourceFacts = SceneResolvedMaterialShaderSchema.graphInputSourceSlotFacts(
        template: liveTemplate, samplers: sourceSamplers, inputIdentity: graphTexture(),
        sourceColorTransfer: liveFrontend.colorTransfer
    )
    cases["samplerProjectionHasSurplusSourceFacts"] = sourceSamplers.keys.sorted() == [0, 2]
        && sourceFacts.keys.sorted() == [0, 2]
    cases["samplerProjectionDropsUnusedSourceSamplerAndFact"] = token(
        frontend, shader: prepared, sourceSamplers: sourceSamplers, observeProjection: true
    ) == "samplers:[0]|facts:[0]"
    cases["samplerProjectionKeepsActuallyBoundSecondSamplerAndFact"] =
        liveFrontend.textureBindings.map(\.slot) == [0, 2] && token(
            liveFrontend, shader: livePrepared, sourceSamplers: sourceSamplers,
            candidateTemplate: liveTemplate, observeProjection: true
        ) == "samplers:[0, 2]|facts:[0, 2]"
    return cases
}
