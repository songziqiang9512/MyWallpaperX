private func runOptionalProviderCases(
    device: MTLDevice,
    queue: MTLCommandQueue,
    source: MTLTexture,
    sourcePipeline: SceneImageLayerPipeline,
    pixelCapabilities: Capabilities,
    chainedMiddleProgramKey: String?,
    pixelClaim: Capabilities.ClaimedLayer?,
    pixelCapability: Capabilities.LayerCapability?,
    colorBlendCapabilities: Capabilities,
    colorBlendClaim: Capabilities.ClaimedLayer?,
    colorBlendCapability: Capabilities.LayerCapability?,
    systemProviderCapabilities: Capabilities,
    systemProviderClaim: Capabilities.ClaimedLayer?,
    systemProviderCapability: Capabilities.LayerCapability?
) -> (
    colorBlendPendingFailure: (prepared: Bool, encoded: Bool, gpuCompleted: Bool, continued: Bool, failureCode: String),
    colorBlendWrongPurposeFailure: (prepared: Bool, encoded: Bool, gpuCompleted: Bool, continued: Bool, failureCode: String),
    systemProviderReadyExecution: (prepared: Bool, encoded: Bool, gpuCompleted: Bool, failureCode: String, stagePixels: [[UInt8]], finalPixel: [UInt8]),
    systemProviderAbsentExecution: (prepared: Bool, encoded: Bool, gpuCompleted: Bool, failureCode: String, stagePixels: [[UInt8]], finalPixel: [UInt8]),
    results: [String: Bool]
) {
    func colorBlendEntries(
        _ kind: ColorBlendMaskFixtureStatus,
        generation: UInt64
    ) -> [SceneFrameTextureIdentity: SceneFrameTextureLookupStatus] {
        [
            .asset(colorBlendMaskIdentity): colorBlendMaskStatus(
                kind,
                device: device,
                generation: generation
            ),
        ]
    }

    let colorBlendPendingFailure = executeVisualFailurePassthrough(
        device: device,
        queue: queue,
        source: source,
        sourcePipeline: sourcePipeline,
        claim: colorBlendClaim,
        capability: colorBlendCapability,
        capabilities: colorBlendCapabilities,
        generation: 12,
        reason: "material-finalizer-optional-texture-unavailable",
        textureEntries: colorBlendEntries(.pending, generation: 12)
    )
    let colorBlendUnavailableFailure = executeVisualFailurePassthrough(
        device: device,
        queue: queue,
        source: source,
        sourcePipeline: sourcePipeline,
        claim: colorBlendClaim,
        capability: colorBlendCapability,
        capabilities: colorBlendCapabilities,
        generation: 13,
        reason: "material-finalizer-optional-texture-unavailable",
        textureEntries: colorBlendEntries(.unavailable, generation: 13)
    )
    let colorBlendWrongPurposeFailure = executeVisualFailurePassthrough(
        device: device,
        queue: queue,
        source: source,
        sourcePipeline: sourcePipeline,
        claim: colorBlendClaim,
        capability: colorBlendCapability,
        capabilities: colorBlendCapabilities,
        generation: 14,
        reason: "material-finalizer-optional-texture-purpose-mismatch",
        textureEntries: colorBlendEntries(.wrongPurpose, generation: 14)
    )
    let colorBlendWrongContentFailure = executeVisualFailurePassthrough(
        device: device,
        queue: queue,
        source: source,
        sourcePipeline: sourcePipeline,
        claim: colorBlendClaim,
        capability: colorBlendCapability,
        capabilities: colorBlendCapabilities,
        generation: 15,
        reason: "material-finalizer-optional-texture-content-mismatch",
        textureEntries: colorBlendEntries(.wrongContent, generation: 15)
    )
    let colorBlendSamplingFailure = executeVisualFailurePassthrough(
        device: device,
        queue: queue,
        source: source,
        sourcePipeline: sourcePipeline,
        claim: colorBlendClaim,
        capability: colorBlendCapability,
        capabilities: colorBlendCapabilities,
        generation: 16,
        reason: "material-finalizer-optional-texture-sampling-unresolved",
        textureEntries: colorBlendEntries(.samplingUnresolved, generation: 16)
    )

    func systemProviderEntries(
        _ kind: SystemProviderFixtureStatus,
        generation: UInt64
    ) -> [SceneFrameTextureIdentity: SceneFrameTextureLookupStatus] {
        var entries: [
            SceneFrameTextureIdentity: SceneFrameTextureLookupStatus
        ] = [
            .asset(systemProviderFallbackIdentity):
                systemProviderFallbackStatus(
                    device: device,
                    generation: generation
                ),
        ]
        if kind != .missing {
            entries[.system(systemProviderIdentity)] = systemProviderStatus(
                kind,
                device: device,
                generation: generation
            )
        }
        return entries
    }

    let systemProviderUnavailableFailure = executeVisualFailurePassthrough(
        device: device,
        queue: queue,
        source: source,
        sourcePipeline: sourcePipeline,
        claim: systemProviderClaim,
        capability: systemProviderCapability,
        capabilities: systemProviderCapabilities,
        generation: 80,
        reason: "material-finalizer-system-provider-unavailable",
        textureEntries: systemProviderEntries(.unavailable, generation: 80)
    )
    let systemProviderPendingFailure = executeVisualFailurePassthrough(
        device: device,
        queue: queue,
        source: source,
        sourcePipeline: sourcePipeline,
        claim: systemProviderClaim,
        capability: systemProviderCapability,
        capabilities: systemProviderCapabilities,
        generation: 83,
        reason: "material-finalizer-system-provider-pending",
        textureEntries: systemProviderEntries(.pending, generation: 83)
    )
    let systemProviderWrongPurposeFailure = executeVisualFailurePassthrough(
        device: device,
        queue: queue,
        source: source,
        sourcePipeline: sourcePipeline,
        claim: systemProviderClaim,
        capability: systemProviderCapability,
        capabilities: systemProviderCapabilities,
        generation: 81,
        reason: "material-finalizer-system-provider-purpose-mismatch",
        textureEntries: systemProviderEntries(.wrongPurpose, generation: 81)
    )
    let systemProviderSamplingFailure = executeVisualFailurePassthrough(
        device: device,
        queue: queue,
        source: source,
        sourcePipeline: sourcePipeline,
        claim: systemProviderClaim,
        capability: systemProviderCapability,
        capabilities: systemProviderCapabilities,
        generation: 82,
        reason: "material-finalizer-system-provider-sampling-unresolved",
        textureEntries: systemProviderEntries(
            .samplingUnresolved,
            generation: 82
        )
    )

    func systemProviderIntegrityFailureRemainsHard(
        _ kind: SystemProviderFixtureStatus,
        generation: UInt64
    ) -> Bool {
        guard let claim = systemProviderClaim,
              let capability = systemProviderCapability,
              let leases = makeChainedLeases(
                capability,
                device: device,
                generation: generation
              ), let executor = Executor(
                device: device,
                capabilities: systemProviderCapabilities
              ), let command = queue.makeCommandBuffer() else {
            return false
        }
        let preparation = executor.prepare(
            token: claim.token,
            leases: leases,
            historyRehydrateCopiesByEffect: [:],
            frame: frame(
                generation,
                textureEntries: systemProviderEntries(
                    kind,
                    generation: generation
                )
            ),
            sourceTexture: source,
            sourceUniforms: .neutral(),
            sourcePipeline: sourcePipeline,
            frameInputs: .init(),
            commandBuffer: command,
            previousStates: [:],
            previousGraphResources: [:],
            effectGeneration: generation,
            resetGeneration: generation
        )
        guard case let .failure(.materialFinalizerRejected(
            stageIndex,
            effect,
            nodeIndex,
            materialOrdinal,
            failure
        )) = preparation else { return false }
        return stageIndex == 1
            && effect == chainedSecondEffect
            && nodeIndex == 1
            && materialOrdinal == 0
            && failure.phase == .texture
            && failure.slot == 1
            && failure.effectLocalVisualFallback == nil
            && command.status == .notEnqueued
    }
    let systemProviderRequestIdentityMismatchRemainsHard =
        systemProviderIntegrityFailureRemainsHard(
            .requestIdentityMismatch,
            generation: 83
        )
    let systemProviderGenerationMismatchRemainsHard =
        systemProviderIntegrityFailureRemainsHard(
            .generationMismatch,
            generation: 84
        )
    let systemProviderMissingRemainsHard =
        systemProviderIntegrityFailureRemainsHard(
            .missing,
            generation: 85
        )
    let systemProviderIncompleteContentRemainsHard =
        systemProviderIntegrityFailureRemainsHard(
            .incompleteContent,
            generation: 86
        )

    func executeSystemProviderSelection(
        _ kind: SystemProviderFixtureStatus,
        generation: UInt64
    ) -> (
        prepared: Bool,
        encoded: Bool,
        gpuCompleted: Bool,
        failureCode: String,
        stagePixels: [[UInt8]],
        finalPixel: [UInt8]
    ) {
        guard let claim = systemProviderClaim,
              let capability = systemProviderCapability,
              let leases = makeChainedLeases(
                capability,
                device: device,
                generation: generation
              ), let executor = Executor(
                device: device,
                capabilities: systemProviderCapabilities
              ), let command = queue.makeCommandBuffer() else {
            return (false, false, false, "setup", [], [])
        }
        let preparation = executor.prepare(
            token: claim.token,
            leases: leases,
            historyRehydrateCopiesByEffect: [:],
            frame: frame(
                generation,
                textureEntries: systemProviderEntries(
                    kind,
                    generation: generation
                )
            ),
            sourceTexture: source,
            sourceUniforms: .neutral(),
            sourcePipeline: sourcePipeline,
            frameInputs: .init(),
            commandBuffer: command,
            previousStates: [:],
            previousGraphResources: [:],
            effectGeneration: generation,
            resetGeneration: generation
        )
        let code = failureCode(preparation)
        guard case let .success(prepared) = preparation,
              prepared.stages.count == 3,
              prepared.stages[1].effectLocalFailureReasonCode == nil,
              prepared.stages[1].programCacheKeys.allSatisfy({
                  !$0.hasPrefix("visual-failure-passthrough:")
              }) else {
            return (false, false, false, code, [], [])
        }
        var stageReadbacks: [Readback] = []
        let encoded = executor.encode(
            prepared,
            commandBuffer: command,
            stageBoundaryObserver: { _, transition, buffer in
                guard let readback = appendReadback(
                    transition.effectOutputResource.publication.texture,
                    commandBuffer: buffer
                ) else { return false }
                stageReadbacks.append(readback)
                return true
            }
        )
        guard encoded,
              let finalReadback = appendReadback(
                prepared.finalTexture,
                commandBuffer: command
              ) else {
            return (true, encoded, false, code, [], [])
        }
        command.commit()
        command.waitUntilCompleted()
        return (
            true,
            encoded,
            command.status == .completed && command.error == nil,
            code,
            stageReadbacks.map(\.firstPixel),
            finalReadback.firstPixel
        )
    }
    let systemProviderReadyExecution = executeSystemProviderSelection(
        .ready,
        generation: 87
    )
    let systemProviderAbsentExecution = executeSystemProviderSelection(
        .absent,
        generation: 88
    )

    func executeColorBlendReady(
        generation: UInt64, sourceTexture: MTLTexture,
        expectedPixels: [[[UInt8]]], expectedFinal: [[UInt8]]
    ) -> (prepared: Bool, encoded: Bool, gpuCompleted: Bool, visible: Bool, premultiplied: Bool) {
        guard let claim = colorBlendClaim, let capability = colorBlendCapability,
              let leases = makeChainedLeases(capability, device: device, generation: generation),
              let executor = Executor(device: device, capabilities: colorBlendCapabilities),
              let command = queue.makeCommandBuffer(), let compositor = makeProductionSourcePipeline(device)
        else { return (false, false, false, false, false) }
        let preparation = executor.prepare(token: claim.token, leases: leases, historyRehydrateCopiesByEffect: [:],
            frame: frame(generation, textureEntries: colorBlendEntries(.ready, generation: generation)),
            sourceTexture: sourceTexture, sourceUniforms: .neutral(), sourcePipeline: sourcePipeline,
            frameInputs: .init(), commandBuffer: command, previousStates: [:], previousGraphResources: [:],
            effectGeneration: generation, resetGeneration: generation)
        guard case let .success(prepared) = preparation, prepared.stages.count == 3,
              prepared.stages[1].effectLocalFailureReasonCode == nil,
              prepared.stages.allSatisfy({ $0.programCacheKeys.allSatisfy { !$0.hasPrefix("visual-failure-passthrough:") } }),
              prepared.finalResource.publication.requestIdentity == .graph(chainedFinalOutput)
        else { return (false, false, false, false, false) }
        var observedStageIndices: [Int] = [], stageReadbacks: [Readback] = []
        let encoded = executor.encode(prepared, commandBuffer: command, stageBoundaryObserver: { i, transition, buffer in
            guard let read = appendReadback(transition.effectOutputResource.publication.texture, commandBuffer: buffer)
            else { return false }
            observedStageIndices.append(i); stageReadbacks.append(read); return true
        })
        guard encoded, let rawFinal = appendReadback(prepared.finalTexture, commandBuffer: command)
        else { return (true, encoded, false, false, false) }
        let terminal = makeSource(device, width: extent.width, height: extent.height,
            usage: [.renderTarget, .shaderRead], bgra: [0, 0, 0, 0])
        let pass = MTLRenderPassDescriptor(); pass.colorAttachments[0].texture = terminal
        pass.colorAttachments[0].loadAction = .clear; pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = .init(red: 0, green: 0, blue: 0, alpha: 0)
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return (true, true, false, false, false) }
        compositor.bind(encoder: encoder)
        var uniforms = SceneLayerFragmentUniforms.neutral()
        uniforms.sourceSampling.y = prepared.finalResource.publication.candidate.content == .color(.resolved(.straightAlpha)) ? 1 : 0
        compositor.drawLayer(texture: prepared.finalTexture, mvp: simd_float4x4(diagonal: SIMD4(2, 2, 1, 1)), uniforms: uniforms, encoder: encoder)
        encoder.endEncoding()
        guard let finalRead = appendReadback(terminal, commandBuffer: command) else { return (true, true, false, false, false) }
        command.commit(); command.waitUntilCompleted()
        // The authored Program publishes straight intermediates. Check every
        // pixel there, then require actual production fragment output to be PMA.
        let typedRaw = prepared.stages.allSatisfy {
            let publication = $0.effectOutputResource.publication
            return publication.isComplete && publication.candidate.purpose == .straightAlbedo
                && publication.candidate.content == .color(.resolved(.straightAlpha))
        }
        let visible = observedStageIndices == [0, 1, 2] && stageReadbacks.count == 3
            && expectedPixels.count == 3 && zip(stageReadbacks, expectedPixels).allSatisfy {
                $0.allTexels.count == 4 && $1.count == 4 && zip($0.allTexels, $1).allSatisfy { matches($0, $1) }
            } && rawFinal.allTexels.count == 4 && zip(rawFinal.allTexels, expectedPixels[2]).allSatisfy { matches($0, $1) }
        let premultiplied = typedRaw && finalRead.allTexels.count == 4 && expectedFinal.count == 4
            && finalRead.allTexels.allSatisfy(isPremultiplied)
            && zip(finalRead.allTexels, expectedFinal).allSatisfy { matches($0, $1) }
        return (true, encoded, command.status == .completed && command.error == nil, visible, premultiplied)
    }
    let colorBlendReady = executeColorBlendReady(generation: 19, sourceTexture: source,
        expectedPixels: [[255, 0, 0, 255], [0, 0, 255, 255], [255, 0, 0, 255]].map { Array(repeating: $0, count: 4) },
        expectedFinal: Array(repeating: [255, 0, 0, 255], count: 4))
    let premultipliedSource = makeSource(device, width: 2, height: 2, pixelsBGRA: [
        0, 0, 0, 0, 8, 16, 48, 64, 16, 32, 96, 128, 0, 0, 0, 0])
    let colorBlendPremultiplied = executeColorBlendReady(generation: 20, sourceTexture: premultipliedSource,
        expectedPixels: [
            [[0, 0, 0, 0], [191, 32, 64, 64], [191, 32, 64, 128], [0, 0, 0, 0]],
            [[0, 0, 255, 0], [0, 0, 255, 64], [0, 0, 255, 128], [0, 0, 255, 0]],
            [[255, 0, 0, 0], [255, 0, 0, 64], [255, 0, 0, 128], [255, 0, 0, 0]]],
        expectedFinal: [[0, 0, 0, 0], [64, 0, 0, 64], [128, 0, 0, 128], [0, 0, 0, 0]])

    func colorBlendIntegrityFailureRemainsHard(
        _ kind: ColorBlendMaskFixtureStatus,
        generation: UInt64
    ) -> Bool {
        guard let claim = colorBlendClaim,
              let capability = colorBlendCapability,
              let leases = makeChainedLeases(
                capability,
                device: device,
                generation: generation
              ), let executor = Executor(
                device: device,
                capabilities: colorBlendCapabilities
              ), let command = queue.makeCommandBuffer() else {
            return false
        }
        let preparation = executor.prepare(
            token: claim.token,
            leases: leases,
            historyRehydrateCopiesByEffect: [:],
            frame: frame(
                generation,
                textureEntries: colorBlendEntries(kind, generation: generation)
            ),
            sourceTexture: source,
            sourceUniforms: .neutral(),
            sourcePipeline: sourcePipeline,
            frameInputs: .init(),
            commandBuffer: command,
            previousStates: [:],
            previousGraphResources: [:],
            effectGeneration: generation,
            resetGeneration: generation
        )
        guard case let .failure(.materialFinalizerRejected(
            stageIndex,
            effect,
            nodeIndex,
            materialOrdinal,
            failure
        )) = preparation else { return false }
        return stageIndex == 1
            && effect == chainedSecondEffect
            && nodeIndex == 1
            && materialOrdinal == 0
            && failure.phase == .texture
            && failure.code == .textureMetadataIncomplete
            && failure.slot == 1
            && failure.effectLocalVisualFallback == nil
            && command.status == .notEnqueued
    }
    let colorBlendGenerationMismatchRemainsHard =
        colorBlendIntegrityFailureRemainsHard(
            .generationMismatch,
            generation: 17
        )
    let colorBlendRequestIdentityMismatchRemainsHard =
        colorBlendIntegrityFailureRemainsHard(
            .requestIdentityMismatch,
            generation: 18
        )

    var rendererFailurePassthroughPrepared = false
    var rendererFailurePassthroughEncoded = false
    var rendererFailurePassthroughGPUCompleted = false
    var rendererFailurePreservesPreviousAndContinuesSuffix = false
    if let claim = pixelClaim,
       let capability = pixelCapability,
       let failedKey = chainedMiddleProgramKey,
       let leases = makeChainedLeases(capability, device: device, generation: 19),
       let executor = Executor(device: device, capabilities: pixelCapabilities),
       let command = queue.makeCommandBuffer() {
        executor.materialEncoder.installTestingPreparationFailure(
            .libraryCompilationRejected(diagnostic: "fixture"),
            preparedKey: failedKey
        )
        let preparation = executor.prepare(
            token: claim.token,
            leases: leases,
            historyRehydrateCopiesByEffect: [:],
            frame: frame(3),
            sourceTexture: source,
            sourceUniforms: .neutral(),
            sourcePipeline: sourcePipeline,
            frameInputs: .init(),
            commandBuffer: command,
            previousStates: [:],
            previousGraphResources: [:],
            effectGeneration: 3,
            resetGeneration: 3
        )
        if case let .success(prepared) = preparation,
           prepared.stages.count == 3,
           prepared.stages[1].programCacheKeys == [
                "visual-failure-passthrough:"
                    + "material-pass-preparation-library-compilation"
           ],
           prepared.stages[1].effectLocalFailureReasonCode
                == "material-pass-preparation-library-compilation" {
            rendererFailurePassthroughPrepared = true
            var observedStageIndices: [Int] = []
            var stageReadbacks: [Readback] = []
            rendererFailurePassthroughEncoded = executor.encode(
                prepared,
                commandBuffer: command,
                stageBoundaryObserver: { stageIndex, transition, buffer in
                    guard let readback = appendReadback(
                        transition.effectOutputResource.publication.texture,
                        commandBuffer: buffer
                    ) else { return false }
                    observedStageIndices.append(stageIndex)
                    stageReadbacks.append(readback)
                    return true
                }
            )
            if rendererFailurePassthroughEncoded,
               let finalReadback = appendReadback(
                   prepared.finalTexture,
                   commandBuffer: command
               ) {
                command.commit()
                command.waitUntilCompleted()
                rendererFailurePassthroughGPUCompleted =
                    command.status == .completed && command.error == nil
                let expectedPixels: [[UInt8]] = [
                    [255, 0, 0, 255],
                    [255, 0, 0, 255],
                    [0, 255, 0, 255],
                ]
                rendererFailurePreservesPreviousAndContinuesSuffix =
                    observedStageIndices == [0, 1, 2]
                    && stageReadbacks.count == 3
                    && zip(stageReadbacks, expectedPixels).allSatisfy {
                        matches($0.firstPixel, $1)
                            && matches($0.lastPixel, $1)
                    }
                    && matches(finalReadback.firstPixel, expectedPixels[2])
                    && matches(finalReadback.lastPixel, expectedPixels[2])
            }
        }
    }
    var terminalAssetResults: [String: Bool] = [:]
    let terminalGraph = chainedGraph()
    let terminalChain = orderedLayerGraph(terminalGraph)
    let middle = terminalGraph.nodes.first {
        $0.kind == .material && $0.effect == chainedSecondEffect
    }!
    let originalMiddle = template(for: middle)
    let projections: [(String, String, SceneTextureLoadPurpose, SceneTextureContent)] = [
        ("PMA", #"{"material":"framebuffer"}"#, .premultipliedColor,
         .color(.resolved(.premultipliedAlpha))),
        ("Straight", #"{"material":"albedo"}"#, .straightAlbedo,
         .color(.resolved(.opaque))),
        ("Data", #"{"mode":"rgbmask"}"#, .preservedChannels, .data),
    ]
    for (index, projection) in projections.enumerated() {
        let (name, metadata, purpose, content) = projection
        let asset = SceneVFSAssetPath("textures/renamed-terminal-\(name).mp4")!
        let identity = SceneAssetTextureIdentity(path: asset, purpose: purpose)
        let shader = shaderContract(
            nodeIndex: middle.nodeIndex,
            pass: false,
            fragmentOverride: """
            varying vec2 v_TexCoord;
            uniform sampler2D g_Texture0; // {"material":"framebuffer"}
            uniform sampler2D g_Texture1; // \(metadata)
            void main() {
                vec4 base = texSample2D(g_Texture0, v_TexCoord);
                vec4 auxiliary = texSample2D(g_Texture1, v_TexCoord);
                gl_FragColor = \(purpose == .premultipliedColor
                    ? "base * auxiliary"
                    : "vec4(mix(base.rgb, auxiliary.rgb, 0.5), base.a)");
            }
            """
        )
        var slots = originalMiddle.textureSlots
        slots[1] = .init(index: 1, candidates: [
            .init(reference: .asset(asset), provenance: .instance),
        ])
        let material = Template.validated(
            textureSlots: slots,
            combos: originalMiddle.combos,
            uniformDeclarations: originalMiddle.uniformDeclarations,
            renderState: originalMiddle.renderState,
            graphRole: originalMiddle.graphRole,
            shaderContract: shader,
            diagnosticProvenance: originalMiddle.diagnosticProvenance
        )!
        var entries = catalog(for: terminalGraph).entries
        entries[.init(effect: middle.effect, nodeIndex: middle.nodeIndex)] = .template(
            material, textureFormatSlots: SceneResolvedMaterialShaderSchema.textureFormatSlots(in: material)
        )
        let terminalCapabilities = capabilities(
            terminalChain,
            catalog: .init(entries: entries, resourceDemandIssues: []),
            assetStates: [identity: .preparedVideo(content)]
        )
        let claim = terminalCapabilities.claim(terminalChain)
        let capability = claim.flatMap { terminalCapabilities.resolve($0.token, for: terminalChain) }
        let generation = UInt64(180 + index * 2)
        let terminal = executeVisualFailurePassthrough(
            device: device, queue: queue, source: source, sourcePipeline: sourcePipeline,
            claim: claim, capability: capability, capabilities: terminalCapabilities,
            generation: generation, reason: "material-finalizer-asset-unavailable",
            textureEntries: [.asset(identity): .unavailable]
        )
        terminalAssetResults["terminal\(name)AssetPreservesPreviousAndContinuesSuffix"] =
            terminal.prepared && terminal.encoded && terminal.gpuCompleted && terminal.continued

        let pendingGeneration = generation + 1
        guard let claim, let capability,
              let leases = makeChainedLeases(capability, device: device, generation: pendingGeneration),
              let executor = Executor(device: device, capabilities: terminalCapabilities),
              let command = queue.makeCommandBuffer() else {
            terminalAssetResults["pending\(name)AssetStillRejectsFrame"] = false
            continue
        }
        let pending = executor.prepare(
            token: claim.token, leases: leases, historyRehydrateCopiesByEffect: [:],
            frame: frame(pendingGeneration, textureEntries: [.asset(identity): .pending]),
            sourceTexture: source, sourceUniforms: .neutral(), sourcePipeline: sourcePipeline,
            frameInputs: .init(), commandBuffer: command, previousStates: [:], previousGraphResources: [:],
            effectGeneration: pendingGeneration, resetGeneration: pendingGeneration
        )
        if case let .failure(.materialFinalizerRejected(stageIndex, failedEffect, _, _, failure)) = pending {
            terminalAssetResults["pending\(name)AssetStillRejectsFrame"] = stageIndex == 1
                && failedEffect == chainedSecondEffect && failure.phase == .texture
                && failure.code == .resourceSnapshotUnresolved && failure.effectLocalVisualFallback == nil
        } else {
            terminalAssetResults["pending\(name)AssetStillRejectsFrame"] = false
        }
    }

    var results: [String: Bool] = [
        "colorBlendMaskPendingPassthroughPrepared":
            colorBlendPendingFailure.prepared,
        "colorBlendReadyPrepared": colorBlendReady.prepared,
        "colorBlendReadyEncoded": colorBlendReady.encoded,
        "colorBlendReadyGPUCompleted": colorBlendReady.gpuCompleted,
        "colorBlendReadyChangesPixelsAndPublishesFinal":
            colorBlendReady.visible,
        "colorBlendReadyPreservesPremultipliedBoundary":
            colorBlendReady.premultiplied,
        "colorBlendTransparentAndPartialAlphaStayPremultiplied":
            colorBlendPremultiplied.prepared
                && colorBlendPremultiplied.encoded
                && colorBlendPremultiplied.gpuCompleted
                && colorBlendPremultiplied.visible
                && colorBlendPremultiplied.premultiplied,
        "colorBlendMaskPendingPassthroughEncoded":
            colorBlendPendingFailure.encoded,
        "colorBlendMaskPendingGPUCompleted":
            colorBlendPendingFailure.gpuCompleted,
        "colorBlendMaskPendingPreservesPreviousAndContinuesSuffix":
            colorBlendPendingFailure.continued,
        "colorBlendMaskUnavailableIsEffectLocal":
            colorBlendUnavailableFailure.prepared
                && colorBlendUnavailableFailure.encoded
                && colorBlendUnavailableFailure.gpuCompleted
                && colorBlendUnavailableFailure.continued,
        "colorBlendMaskWrongPurposeIsEffectLocal":
            colorBlendWrongPurposeFailure.prepared
                && colorBlendWrongPurposeFailure.encoded
                && colorBlendWrongPurposeFailure.gpuCompleted
                && colorBlendWrongPurposeFailure.continued,
        "colorBlendMaskWrongContentIsEffectLocal":
            colorBlendWrongContentFailure.prepared
                && colorBlendWrongContentFailure.encoded
                && colorBlendWrongContentFailure.gpuCompleted
                && colorBlendWrongContentFailure.continued,
        "colorBlendMaskSamplingFailureIsEffectLocal":
            colorBlendSamplingFailure.prepared
                && colorBlendSamplingFailure.encoded
                && colorBlendSamplingFailure.gpuCompleted
                && colorBlendSamplingFailure.continued,
        "colorBlendMaskGenerationMismatchRemainsHard":
            colorBlendGenerationMismatchRemainsHard,
        "colorBlendMaskRequestIdentityMismatchRemainsHard":
            colorBlendRequestIdentityMismatchRemainsHard,
        "systemProviderUnavailablePassthroughPrepared":
            systemProviderUnavailableFailure.prepared,
        "systemProviderUnavailablePassthroughEncoded":
            systemProviderUnavailableFailure.encoded,
        "systemProviderUnavailableGPUCompleted":
            systemProviderUnavailableFailure.gpuCompleted,
        "systemProviderUnavailablePreservesPreviousAndContinuesSuffix":
            systemProviderUnavailableFailure.continued,
        "systemProviderPendingIsEffectLocal":
            systemProviderPendingFailure.prepared
                && systemProviderPendingFailure.encoded
                && systemProviderPendingFailure.gpuCompleted
                && systemProviderPendingFailure.continued,
        "systemProviderWrongPurposeIsEffectLocal":
            systemProviderWrongPurposeFailure.prepared
                && systemProviderWrongPurposeFailure.encoded
                && systemProviderWrongPurposeFailure.gpuCompleted
                && systemProviderWrongPurposeFailure.continued,
        "systemProviderSamplingUnresolvedIsEffectLocal":
            systemProviderSamplingFailure.prepared
                && systemProviderSamplingFailure.encoded
                && systemProviderSamplingFailure.gpuCompleted
                && systemProviderSamplingFailure.continued,
        "systemProviderRequestIdentityMismatchRemainsHard":
            systemProviderRequestIdentityMismatchRemainsHard,
        "systemProviderGenerationMismatchRemainsHard":
            systemProviderGenerationMismatchRemainsHard,
        "systemProviderMissingRegistryEntryRemainsHard":
            systemProviderMissingRemainsHard,
        "systemProviderIncompleteContentRemainsHard":
            systemProviderIncompleteContentRemainsHard,
        "systemProviderReadyExactExecutesProgramAndGPU":
            systemProviderReadyExecution.prepared
                && systemProviderReadyExecution.encoded
                && systemProviderReadyExecution.gpuCompleted,
        "systemProviderReadyExactChangesMiddleStagePixels":
            systemProviderReadyExecution.stagePixels.count == 3
                && matches(
                    systemProviderReadyExecution.stagePixels[0],
                    [255, 0, 0, 255]
                )
                && matches(
                    systemProviderReadyExecution.stagePixels[1],
                    [0, 0, 0, 255]
                )
                && matches(
                    systemProviderReadyExecution.stagePixels[2],
                    [0, 0, 0, 255]
                )
                && matches(
                    systemProviderReadyExecution.finalPixel,
                    [0, 0, 0, 255]
                ),
        "systemProviderAbsentUsesLowerAssetWithoutFallback":
            systemProviderAbsentExecution.prepared
                && systemProviderAbsentExecution.encoded
                && systemProviderAbsentExecution.gpuCompleted
                && systemProviderAbsentExecution.stagePixels.count == 3
                && matches(
                    systemProviderAbsentExecution.stagePixels[0],
                    [255, 0, 0, 255]
                )
                && matches(
                    systemProviderAbsentExecution.stagePixels[1],
                    [255, 0, 0, 255]
                )
                && matches(
                    systemProviderAbsentExecution.stagePixels[2],
                    [0, 255, 0, 255]
                )
                && matches(
                    systemProviderAbsentExecution.finalPixel,
                    [0, 255, 0, 255]
                ),
        "rendererFailurePassthroughPrepared":
            rendererFailurePassthroughPrepared,
        "rendererFailurePassthroughEncoded":
            rendererFailurePassthroughEncoded,
        "rendererFailurePassthroughGPUCompleted":
            rendererFailurePassthroughGPUCompleted,
        "rendererFailurePreservesPreviousAndContinuesSuffix":
            rendererFailurePreservesPreviousAndContinuesSuffix,
    ]
    results.merge(terminalAssetResults) { _, new in new }
    return (
        colorBlendPendingFailure,
        colorBlendWrongPurposeFailure,
        systemProviderReadyExecution,
        systemProviderAbsentExecution,
        results
    )
}
