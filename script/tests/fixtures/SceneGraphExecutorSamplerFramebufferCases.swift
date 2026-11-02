private func runAddressCases(
    device: MTLDevice,
    queue: MTLCommandQueue,
    source: MTLTexture,
    sourcePipeline: SceneImageLayerPipeline,
    ordinaryGraph: Graph,
    scalarGraph: Graph
) -> (
    scalarUniqueGraph: Graph,
    scalarNoConsumerGraph: Graph,
    scalarMultipleWriterGraph: Graph,
    scalarCopyGraph: Graph,
    scalarSwapGraph: Graph,
    rgbaClampProbe: (executed: Bool, publicationMatches: Bool, first: [UInt8], last: [UInt8]),
    rgbaRepeatProbe: (executed: Bool, publicationMatches: Bool, first: [UInt8], last: [UInt8]),
    scalarClampProbe: (executed: Bool, publicationMatches: Bool, first: [UInt8], last: [UInt8]),
    scalarRepeatProbe: (executed: Bool, publicationMatches: Bool, first: [UInt8], last: [UInt8]),
    results: [String: Bool]
) {
    let scalarUniqueGraph = graph(
        targets: [rawTarget(first, format: "r8", unique: true)],
        nodes: [
            material(0, ordinal: 0, target: first, read: input),
            material(1, ordinal: 1, target: output, read: first),
        ]
    )
    let scalarNoConsumerGraph = graph(
        targets: [rawTarget(first, format: "r8")],
        nodes: [
            material(0, ordinal: 0, target: first, read: input),
            material(1, ordinal: 1, target: output, read: input),
        ]
    )
    let scalarMultipleWriterGraph = graph(
        targets: [rawTarget(first, format: "r8")],
        nodes: [
            material(0, ordinal: 0, target: first, read: input),
            material(1, ordinal: 1, target: first, read: input),
            material(2, ordinal: 2, target: output, read: first),
        ]
    )
    let scalarCopyGraph = graph(
        targets: [
            rawTarget(first, format: "r8"),
            rawTarget(second, format: "r8"),
        ],
        nodes: [
            material(0, ordinal: 0, target: first, read: input),
            command(1, kind: .copy, source: first, target: second),
            material(2, ordinal: 1, target: output, read: second),
        ]
    )
    let scalarSwapGraph = graph(
        targets: [
            rawTarget(first, format: "r8", unique: true),
            rawTarget(second, format: "r8", unique: true),
        ],
        nodes: [
            material(0, ordinal: 0, target: second, read: first),
            command(1, kind: .swap, source: first, target: second),
            material(2, ordinal: 1, target: output, read: first),
        ]
    )
    let scalarRepeatGraph = graph(
        targets: [rawTarget(
            first,
            format: "r8",
            uvs: .string("repeat")
        )],
        nodes: [
            material(0, ordinal: 0, target: first, read: input),
            material(1, ordinal: 1, target: output, read: first),
        ]
    )
    let rgbaRepeatGraph = graph(
        targets: [rawTarget(first, uvs: .string("repeat"))],
        nodes: [
            material(0, ordinal: 0, target: first, read: input),
            material(1, ordinal: 1, target: output, read: first),
        ]
    )

    func addressProbe(
        _ graph: Graph,
        scalar: Bool,
        expectedSampling: SceneTextureSampling,
        generation: UInt64
    ) -> (
        executed: Bool,
        publicationMatches: Bool,
        first: [UInt8],
        last: [UInt8]
    ) {
        let chain = admittedGraph(graph)
        let capabilitySet = capabilities(
            chain,
            catalog: catalog(
                for: graph,
                scalarConsumerNodes: scalar ? [1: "red"] : [:],
                repeatProbeNodes: [1]
            )
        )
        guard let claim = capabilitySet.claim(chain),
              let executor = Executor(
                  device: device,
                  capabilities: capabilitySet
              ), let command = queue.makeCommandBuffer() else {
            return (false, false, [], [])
        }
        let lease = makeLease(
            requirePlan(graph),
            device: device,
            generation: generation
        )
        let pattern = makeSource(
            device,
            width: 2,
            height: 2,
            pixelsBGRA: [
                0, 0, 64, 255,
                0, 0, 128, 255,
                0, 0, 192, 255,
                0, 0, 255, 255,
            ]
        )
        let preparation = executor.prepare(
            token: claim.token,
            leases: [lease],
            historyRehydrateCopiesByEffect: [:],
            frame: frame(generation),
            sourceTexture: pattern,
            sourceUniforms: .neutral(),
            sourcePipeline: sourcePipeline,
            frameInputs: .init(),
            commandBuffer: command,
            previousStates: [:],
            previousGraphResources: [:],
            effectGeneration: generation,
            resetGeneration: generation
        )
        guard case let .success(prepared) = preparation,
              let stage = prepared.stages.first,
              let publication = stage.frameResources[first] else {
            return (false, false, [], [])
        }
        let publicationMatches = stage.programCacheKeys.count == 2
            && publication.publication.requestIdentity == .graph(first)
            && publication.publication.candidate.sampling
                == expectedSampling
            && publication.publication.candidate.sampling.rawFlags == nil
            && (scalar
                ? publication.publication.candidate.content
                    == .scalarRedUnorm
                : publication.publication.candidate.content
                    != .scalarRedUnorm)
        let encoded = executor.encode(prepared, commandBuffer: command)
        guard let readback = appendReadback(
            prepared.finalTexture,
            commandBuffer: command
        ) else { return (false, publicationMatches, [], []) }
        command.commit()
        command.waitUntilCompleted()
        return (
            encoded && command.status == .completed && command.error == nil,
            publicationMatches,
            readback.firstPixel,
            readback.lastPixel
        )
    }

    let rgbaClampProbe = addressProbe(
        ordinaryGraph,
        scalar: false,
        expectedSampling: .linearClamp,
        generation: 81
    )
    let rgbaRepeatProbe = addressProbe(
        rgbaRepeatGraph,
        scalar: false,
        expectedSampling: .linearRepeat,
        generation: 82
    )
    let scalarClampProbe = addressProbe(
        scalarGraph,
        scalar: true,
        expectedSampling: .linearClamp,
        generation: 83
    )
    let scalarRepeatProbe = addressProbe(
        scalarRepeatGraph,
        scalar: true,
        expectedSampling: .linearRepeat,
        generation: 84
    )
    let results: [String: Bool] = [
        "rgbaClampProbeExecutes": rgbaClampProbe.executed,
        "rgbaClampPublicationIsTyped": rgbaClampProbe.publicationMatches,
        "rgbaClampProbeClampsOutOfRangeUV": matches(
            rgbaClampProbe.first,
            [0, 0, 255, 255]
        ) && matches(rgbaClampProbe.last, [0, 0, 255, 255]),
        "rgbaRepeatProbeExecutes": rgbaRepeatProbe.executed,
        "rgbaRepeatPublicationIsTyped": rgbaRepeatProbe.publicationMatches,
        "rgbaRepeatProbeWrapsOutOfRangeUV": matches(
            rgbaRepeatProbe.first,
            [0, 0, 64, 255]
        ) && matches(rgbaRepeatProbe.last, [0, 0, 255, 255]),
        "scalarClampProbeExecutes": scalarClampProbe.executed,
        "scalarClampPublicationIsTyped": scalarClampProbe.publicationMatches,
        "scalarClampProbeClampsOutOfRangeUV": matches(
            scalarClampProbe.first,
            [0, 0, 255, 255]
        ) && matches(scalarClampProbe.last, [0, 0, 255, 255]),
        "scalarRepeatProbeExecutes": scalarRepeatProbe.executed,
        "scalarRepeatPublicationIsTyped": scalarRepeatProbe.publicationMatches,
        "scalarRepeatProbeWrapsOutOfRangeUV": matches(
            scalarRepeatProbe.first,
            [0, 0, 64, 255]
        ) && matches(scalarRepeatProbe.last, [0, 0, 255, 255]),
    ]
    return (
        scalarUniqueGraph,
        scalarNoConsumerGraph,
        scalarMultipleWriterGraph,
        scalarCopyGraph,
        scalarSwapGraph,
        rgbaClampProbe,
        rgbaRepeatProbe,
        scalarClampProbe,
        scalarRepeatProbe,
        results
    )
}

private func runFramebufferCases(
    device: MTLDevice,
    queue: MTLCommandQueue,
    source: MTLTexture,
    sourcePipeline: SceneImageLayerPipeline,
    ordinaryClaim: Capabilities.ClaimedLayer,
    ordinaryExecutor: Executor,
    ordinaryLease: SceneGraphRenderTargetLease
) -> (
    rtDefaultResults: [String: Bool],
    results: [String: Bool]
) {
    let implicitFramebufferGraph = graph(
        targets: [],
        nodes: [
            implicitFramebufferMaterial(0, ordinal: 0, target: output),
        ]
    )
    let implicitFramebufferChain = admittedGraph(implicitFramebufferGraph)
    let implicitFramebufferCapabilities = capabilities(
        implicitFramebufferChain,
        catalog: catalog(
            for: implicitFramebufferGraph,
            implicitFramebufferNodes: [0]
        )
    )
    let implicitFramebufferClaim = implicitFramebufferCapabilities.claim(
        implicitFramebufferChain
    )!
    let implicitFramebufferExecutor = Executor(
        device: device,
        capabilities: implicitFramebufferCapabilities
    )!
    let implicitFramebufferLease = makeLease(
        requireR4Plan(implicitFramebufferGraph),
        device: device
    )
    guard let implicitFramebufferBuffer = queue.makeCommandBuffer() else {
        fatalError("implicit framebuffer buffer unavailable")
    }
    let implicitFramebufferPreparation = implicitFramebufferExecutor.prepare(
        token: implicitFramebufferClaim.token,
        leases: [implicitFramebufferLease],
        historyRehydrateCopiesByEffect: [:],
        frame: frame(0),
        sourceTexture: source,
        sourceUniforms: .neutral(),
        sourcePipeline: sourcePipeline,
        frameInputs: .init(),
        commandBuffer: implicitFramebufferBuffer,
        previousStates: [:],
        previousGraphResources: [:],
        effectGeneration: 1,
        resetGeneration: 1
    )

    var rtDefaultResults: [String: Bool] = [:]
    for suffix in ["", "_a", "_b"] {
        for availability in ["noCandidate", "absent", "ready"] {
            let token = "_rt_imageLayerComposite_\(layerID)\(suffix)"
            let path = SceneVFSAssetPath("textures/rf01-missing.tex")!
            let identity = SceneAssetTextureIdentity(path: path, purpose: .straightAlbedo)
            let node = implicitFramebufferGraph.nodes[0]
            let rtTemplate = implicitFramebufferTemplate(for: node, renderTargetDefault: token,
                candidateAsset: availability == "noCandidate" ? nil : path)
            let rtCatalog = SceneResolvedMaterialRuntimeCatalog(entries: [
                .init(effect: node.effect, nodeIndex: node.nodeIndex): .template(rtTemplate, textureFormatSlots: SceneResolvedMaterialShaderSchema.textureFormatSlots(in: rtTemplate))], resourceDemandIssues: [])
            let assetStates: [SceneAssetTextureIdentity: SceneAssetTextureLaunchState] = availability == "noCandidate" ? [:]
                : [identity: availability == "absent" ? .absent : .ready(.color(.resolved(.straightAlpha)))]
            let rtCapabilities = capabilities(implicitFramebufferChain, catalog: rtCatalog, assetStates: assetStates)
            for alpha: UInt8 in [255, 128] {
                let key = "\(token):\(availability):alpha-\(alpha)"
                guard let claim = rtCapabilities.claim(implicitFramebufferChain),
                      let executor = Executor(device: device, capabilities: rtCapabilities),
                      let compositor = makeProductionSourcePipeline(device) else {
                    rtDefaultResults[key + ":admitted"] = false; continue
                }
                rtDefaultResults[key + ":admitted"] = true
                let lease = makeLease(requireR4Plan(implicitFramebufferGraph), device: device, generation: 96)
                for index: UInt64 in [96, 97] {
                    let buffer = queue.makeCommandBuffer()!
                    let source = makeSource(device, bgra: index == 96 ? [0, 0, alpha, alpha] : [0, alpha, 0, alpha])
                    var entries: [SceneFrameTextureIdentity: SceneFrameTextureLookupStatus] = [:]
                    if availability == "absent" { entries[.asset(identity)] = .absent }
                    if availability == "ready" {
                        let candidate = SceneTextureCandidate(texture: makeSource(device, bgra: [255, 0, 0, 128]),
                            identity: .builtIn(name: "self-ready-straight"), generation: .immutable(revision: 1),
                            purpose: .straightAlbedo, content: .color(.resolved(.straightAlpha)),
                            physicalSize: CGSize(width: 1, height: 1), mappedSize: CGSize(width: 1, height: 1),
                            uvTransform: .identity, sampling: .linearClamp)
                        entries[.asset(identity)] = .ready(.init(publication: .init(requestIdentity: .asset(identity),
                            candidate: candidate, contentGeneration: index), resourceGeneration: index))
                    }
                    let preparation = executor.prepare(token: claim.token, leases: [lease], historyRehydrateCopiesByEffect: [:],
                        frame: frame(index, textureEntries: entries), sourceTexture: source, sourceUniforms: .neutral(),
                        sourcePipeline: sourcePipeline, frameInputs: .init(), commandBuffer: buffer,
                        previousStates: [:], previousGraphResources: [:], effectGeneration: 96, resetGeneration: 96)
                    guard case let .success(prepared) = preparation, executor.encode(prepared, commandBuffer: buffer),
                          let raw = appendReadback(prepared.finalTexture, commandBuffer: buffer) else {
                        rtDefaultResults[key + ":frame-\(index)"] = false; continue
                    }
                    let terminal = makeSource(device, width: extent.width, height: extent.height,
                        usage: [.renderTarget, .shaderRead], bgra: [0, 0, 0, 0])
                    let pass = MTLRenderPassDescriptor(); pass.colorAttachments[0].texture = terminal
                    pass.colorAttachments[0].loadAction = .clear; pass.colorAttachments[0].storeAction = .store
                    pass.colorAttachments[0].clearColor = .init(red: 0, green: 0, blue: 0, alpha: 0)
                    let encoder = buffer.makeRenderCommandEncoder(descriptor: pass)!
                    compositor.bind(encoder: encoder)
                    var uniforms = SceneLayerFragmentUniforms.neutral()
                    uniforms.sourceSampling.y = prepared.finalResource.publication.candidate.content == .color(.resolved(.straightAlpha)) ? 1 : 0
                    compositor.drawLayer(texture: prepared.finalTexture, mvp: simd_float4x4(diagonal: SIMD4(2, 2, 1, 1)), uniforms: uniforms, encoder: encoder)
                    encoder.endEncoding(); let final = appendReadback(terminal, commandBuffer: buffer)!
                    buffer.commit(); buffer.waitUntilCompleted()
                    let publication = prepared.finalResource.publication
                    let expectedRaw: [UInt8] = availability == "ready" ? [0, 255, 0, 128]
                        : index == 96 ? [255, 0, 0, alpha] : [0, 0, 255, alpha]
                    let expectedFinal: [UInt8] = availability == "ready" ? [0, 128, 0, 128]
                        : index == 96 ? [alpha, 0, 0, alpha] : [0, 0, alpha, alpha]
                    rtDefaultResults[key + ":frame-\(index)"] = prepared.stages.count == 1
                        && publication.requestIdentity == .graph(output) && publication.isComplete
                        && publication.candidate.purpose == .straightAlbedo
                        && publication.candidate.content == .color(.resolved(.straightAlpha))
                        && buffer.status == .completed && buffer.error == nil
                        && raw.allTexels.count == 4 && raw.allTexels.allSatisfy { matches($0, expectedRaw) }
                        && final.allTexels.count == 4 && final.allTexels.allSatisfy { matches($0, expectedFinal) && isPremultiplied($0) }
                }
            }
        }
    }

    let historicalFramebufferCapabilities = capabilities(
        implicitFramebufferChain,
        catalog: catalog(
            for: implicitFramebufferGraph,
            implicitFramebufferNodes: [0],
            historicalFramebufferNodes: [0]
        )
    )
    let historicalFramebufferClaim = historicalFramebufferCapabilities.claim(
        implicitFramebufferChain
    )!
    let historicalFramebufferExecutor = Executor(
        device: device,
        capabilities: historicalFramebufferCapabilities
    )!
    let historicalFramebufferLease = makeLease(
        requireR4Plan(implicitFramebufferGraph),
        device: device
    )
    guard let historicalFramebufferBuffer = queue.makeCommandBuffer() else {
        fatalError("historical framebuffer buffer unavailable")
    }
    let historicalFramebufferPreparation = historicalFramebufferExecutor.prepare(
        token: historicalFramebufferClaim.token,
        leases: [historicalFramebufferLease],
        historyRehydrateCopiesByEffect: [:],
        frame: frame(0),
        sourceTexture: source,
        sourceUniforms: .neutral(),
        sourcePipeline: sourcePipeline,
        frameInputs: .init(),
        commandBuffer: historicalFramebufferBuffer,
        previousStates: [:],
        previousGraphResources: [:],
        effectGeneration: 1,
        resetGeneration: 1
    )
    var historicalFramebufferPublication = false
    var historicalFramebufferEncoded = false
    if case let .success(prepared) = historicalFramebufferPreparation {
        historicalFramebufferPublication = prepared.stages.count == 1
            && prepared.stages[0].effectOutputResource.publication.requestIdentity
                == .graph(output)
            && prepared.stages[0].programCacheKeys.count == 1
        historicalFramebufferEncoded = historicalFramebufferExecutor.encode(
            prepared,
            commandBuffer: historicalFramebufferBuffer
        )
        guard let readback = appendReadback(
            prepared.finalTexture,
            commandBuffer: historicalFramebufferBuffer
        ) else { fatalError("historical framebuffer readback unavailable") }
        historicalFramebufferBuffer.commit()
        historicalFramebufferBuffer.waitUntilCompleted()
        historicalFramebufferEncoded = historicalFramebufferEncoded
            && historicalFramebufferBuffer.status == .completed
            && historicalFramebufferBuffer.error == nil
            && matches(readback.firstPixel, [0, 0, 255, 255])
    }

    guard let unreadableCaptureBuffer = queue.makeCommandBuffer() else {
        fatalError("unreadable source capture buffer unavailable")
    }
    let unreadableCapturePreparation = ordinaryExecutor.prepare(
        token: ordinaryClaim.token,
        leases: [ordinaryLease],
        historyRehydrateCopiesByEffect: [:],
        frame: frame(0),
        sourceTexture: makeSource(device, usage: .renderTarget),
        sourceUniforms: .neutral(),
        sourcePipeline: sourcePipeline,
        frameInputs: .init(),
        commandBuffer: unreadableCaptureBuffer,
        previousStates: [:],
        previousGraphResources: [:],
        effectGeneration: 1,
        resetGeneration: 1
    )
    let results: [String: Bool] = [
        "implicitFramebufferStructuralInferenceBindsEffectInput":
            failureCode(implicitFramebufferPreparation) == "success",
        "rtShaderDefaultsBindAndPublishAcrossFrames": rtDefaultResults.count == 54 && rtDefaultResults.values.allSatisfy { $0 },
        "historicalFramebufferAliasBindsEffectInput":
            failureCode(historicalFramebufferPreparation) == "success",
        "historicalFramebufferAliasPublishesTypedOutput":
            historicalFramebufferPublication,
        "historicalFramebufferAliasEncodesOnGPU": historicalFramebufferEncoded,
        "unreadableSourceCaptureRejectedDuringPreflight":
            failureCode(unreadableCapturePreparation)
                == Executor.Failure.captureRejected.rawValue,
    ]
    return (
        rtDefaultResults,
        results
    )
}
