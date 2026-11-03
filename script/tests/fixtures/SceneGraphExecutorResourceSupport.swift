private func requirePlan(
    _ graph: Graph,
    width: Int = extent.width,
    height: Int = extent.height
) -> Plan {
    switch Plan.make(
        graph: graph,
        inputRole: .layerSource,
        inputWidth: width,
        inputHeight: height
    ) {
    case let .success(value): value
    case let .failure(failure): fatalError("plan failed: \(failure.rawValue)")
    }
}

private func requireMaterialFunctionPlan(_ graph: Graph) -> Plan {
    switch Plan.make(
        graph: graph,
        inputRole: .layerSource,
        inputWidth: extent.width,
        inputHeight: extent.height,
        materialFunctionTargets: [first]
    ) {
    case let .success(value): value
    case let .failure(failure):
        fatalError("material function plan failed: \(failure.rawValue)")
    }
}

private func requireR4Plan(_ graph: Graph) -> Plan {
    switch Plan.make(
        graph: graph,
        inputRole: .layerSource,
        inputWidth: extent.width,
        inputHeight: extent.height
    ) {
    case let .success(value): value
    case let .failure(failure): fatalError("R4 plan failed: \(failure.rawValue)")
    }
}

private func makeLease(
    _ plan: Plan,
    device: MTLDevice,
    generation: UInt64 = 7
) -> SceneGraphRenderTargetLease {
    let table: SceneGraphRenderTargetTable
    switch SceneGraphRenderTargetTable.make(
        plan: plan,
        device: device,
        byteBudget: 1_048_576
    ) {
    case let .success(value): table = value
    case let .failure(failure): fatalError("table failed: \(failure.rawValue)")
    }
    var ordinal = 0
    switch SceneGraphRenderTargetLease.make(
        table: table,
        generation: generation,
        tokenForTexture: { _ in
            defer { ordinal += 1 }
            return .init(rawValue: "executor-physical-\(generation)-\(ordinal)")
        }
    ) {
    case let .success(value): return value
    case let .failure(failure): fatalError("lease failed: \(failure.rawValue)")
    }
}

private func makeChainedLeases(
    _ capability: Capabilities.LayerCapability,
    device: MTLDevice,
    generation: UInt64 = 17
) -> [SceneGraphRenderTargetLease]? {
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .bgra8Unorm,
        width: extent.width,
        height: extent.height,
        mipmapped: false
    )
    descriptor.storageMode = .private
    descriptor.usage = [.renderTarget, .shaderRead]
    guard let zero = device.makeTexture(descriptor: descriptor),
          let one = device.makeTexture(descriptor: descriptor) else { return nil }
    let zeroToken = Executor.State.PhysicalToken(rawValue: "pixel-admittedGraph-zero")
    let oneToken = Executor.State.PhysicalToken(rawValue: "pixel-admittedGraph-one")
    func texture(_ member: SceneLayerFullFramePairPlan.Member) -> MTLTexture {
        member == .zero ? zero : one
    }
    var leases: [SceneGraphRenderTargetLease] = []
    for index in capability.admittedProducts.indices {
        let graph = capability.admittedProducts[index].graph
        let role: SceneAuthoredEffectInputRole = index == 0
            ? .layerSource : .priorEffectOutput
        let plan: Plan
        switch Plan.make(
            graph: graph,
            inputRole: role,
            inputWidth: extent.width,
            inputHeight: extent.height
        ) {
        case let .success(value): plan = value
        case .failure: return nil
        }
        let step = capability.pairPlan.effects[index]
        var texturesByIdentity = [
            plan.input: texture(step.inputMember),
            plan.output: texture(step.outputMember),
        ]
        var tokensByObject: [ObjectIdentifier: Executor.State.PhysicalToken] = [
            ObjectIdentifier(zero): zeroToken, ObjectIdentifier(one): oneToken,
        ]
        guard let specifications = SceneGraphRenderTargetTable.specifications(for: plan) else { return nil }
        for specification in specifications where
            specification.identity != plan.input && specification.identity != plan.output {
            let targetDescriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: specification.format.metalPixelFormat,
                width: specification.extent.width, height: specification.extent.height, mipmapped: false)
            targetDescriptor.storageMode = .private
            targetDescriptor.usage = [.renderTarget, .shaderRead]
            guard let target = device.makeTexture(descriptor: targetDescriptor) else { return nil }
            texturesByIdentity[specification.identity] = target
            tokensByObject[ObjectIdentifier(target)] = .init(rawValue:
                "pixel-admittedGraph-target-\(index)-\(tokensByObject.count)")
        }
        let mapped: SceneGraphRenderTargetTable
        switch SceneGraphRenderTargetTable.makeMapped(
            plan: plan,
            device: device,
            texturesByIdentity: texturesByIdentity,
            fullFramePair: .init(first: zero, second: one),
            expectsInputOutputAlias: step.inputMember == step.outputMember,
            makeInputsDigest: 0
        ) {
        case let .success(value): mapped = value
        case .failure: return nil
        }
        let lease: SceneGraphRenderTargetLease
        switch SceneGraphRenderTargetLease.make(
            table: mapped,
            generation: generation,
            tokenForTexture: { object in
                tokensByObject[ObjectIdentifier(object)]!
            },
            fullFramePairGeneration: generation,
            tokenForPairTexture: { object in
                object === zero ? zeroToken : oneToken
            }
        ) {
        case let .success(value): lease = value
        case .failure: return nil
        }
        leases.append(lease)
    }
    return leases
}

private func manualPlan(
    targets: [Plan.LogicalTarget],
    commands: [Plan.Command]
) -> Plan {
    .testingPlan(
        layerID: layerID,
        input: input,
        output: output,
        inputExtent: extent,
        logicalTargets: targets,
        commands: commands
    )
}

private func logical(
    _ identity: Graph.TextureIdentity,
    width: Int = 2,
    height: Int = 2,
    format: Plan.TextureFormat = .rgbaBackbuffer,
    addressMode: Plan.UVAddressMode = .clampToEdge,
    unique: Bool = false,
    firstWrite: Int,
    lastWrite: Int,
    firstRead: Int?,
    lastRead: Int?
) -> Plan.LogicalTarget {
    .init(
        identity: identity,
        extent: .init(width: width, height: height),
        format: format,
        addressMode: addressMode,
        isUnique: unique,
        lifetime: .init(
            firstWriteNodeIndex: firstWrite,
            lastWriteNodeIndex: lastWrite,
            firstReadNodeIndex: firstRead,
            lastReadNodeIndex: lastRead
        ),
        initialClear: nil
    )
}

private func makeSource(
    _ device: MTLDevice,
    width: Int = 1,
    height: Int = 1,
    usage: MTLTextureUsage = .shaderRead,
    bgra: [UInt8] = [0, 0, 255, 255],
    pixelsBGRA: [UInt8]? = nil,
    pixelFormat: MTLPixelFormat = .bgra8Unorm
) -> MTLTexture {
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: pixelFormat,
        width: width,
        height: height,
        mipmapped: false
    )
    descriptor.storageMode = .shared
    descriptor.usage = usage
    let texture = device.makeTexture(descriptor: descriptor)!
    precondition(bgra.count == 4)
    let pixels = pixelsBGRA ?? (0 ..< width * height).flatMap { _ in bgra }
    precondition(pixels.count == width * height * 4)
    texture.replace(
        region: MTLRegionMake2D(0, 0, width, height),
        mipmapLevel: 0,
        withBytes: pixels,
        bytesPerRow: width * 4
    )
    return texture
}

private func makeSourcePipeline(_ device: MTLDevice) -> SceneImageLayerPipeline {
    let source = """
    #include <metal_stdlib>
    using namespace metal;
    struct Vertex { float2 position; float2 texcoord; float vertexCoverage; };
    struct Varying { float4 position [[position]]; float2 texcoord; };
    struct Uniforms {
        float time;
        float alpha;
        uint dependencyBlendMode;
        uint usesDependencyBlend;
        float2 cursorUV;
        uint2 sourceSampling;
        float4 tint;
        float4 textureFrame0;
        float4 textureFrame1;
    };
    vertex Varying fixtureVertex(
        const device Vertex *vertices [[buffer(0)]],
        constant float4x4 &mvp [[buffer(1)]],
        uint id [[vertex_id]]
    ) {
        Varying out;
        out.position = mvp * float4(vertices[id].position, 0, 1);
        out.texcoord = vertices[id].texcoord;
        return out;
    }
    fragment float4 fixtureFragment(
        Varying in [[stage_in]],
        texture2d<float> source [[texture(0)]],
        constant Uniforms &uniforms [[buffer(0)]]
    ) {
        constexpr sampler s(coord::normalized, address::clamp_to_edge,
                            filter::nearest);
        return source.sample(s, in.texcoord) * uniforms.tint;
    }
    """
    let library = try! device.makeLibrary(source: source, options: nil)
    let descriptor = MTLRenderPipelineDescriptor()
    descriptor.vertexFunction = library.makeFunction(name: "fixtureVertex")
    descriptor.fragmentFunction = library.makeFunction(name: "fixtureFragment")
    descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
    return .init(state: try! device.makeRenderPipelineState(descriptor: descriptor))
}

// The graph gate supplies a small Swift binding shell, but this path executes
// the production image compositor fragment from the frozen default library.
private func makeProductionSourcePipeline(_ device: MTLDevice) -> SceneImageLayerPipeline? {
    guard let library = device.makeDefaultLibrary(),
          let vertex = library.makeFunction(name: "sceneImageLayerVert") else { return nil }
    let constants = MTLFunctionConstantValues()
    var weightsSourceAlpha = false
    constants.setConstantValue(&weightsSourceAlpha, type: .bool, index: 0)
    guard let fragment = try? library.makeFunction(name: "sceneImageLayerFrag", constantValues: constants)
    else { return nil }
    let descriptor = MTLRenderPipelineDescriptor()
    descriptor.vertexFunction = vertex; descriptor.fragmentFunction = fragment
    descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
    descriptor.colorAttachments[0].isBlendingEnabled = true
    descriptor.colorAttachments[0].sourceRGBBlendFactor = .one
    descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
    descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
    descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
    guard let state = try? device.makeRenderPipelineState(descriptor: descriptor) else { return nil }
    return .init(state: state)
}

private func frame(
    _ index: UInt64,
    width: Int = extent.width,
    height: Int = extent.height,
    dynamicDefinitions: [SceneDynamicTargetDefinition] = [],
    timelineValues: [SceneDynamicTarget: SceneDynamicValue] = [:],
    sceneTime: Float? = nil,
    textureEntries: [
        SceneFrameTextureIdentity: SceneFrameTextureLookupStatus
    ] = [:]
) -> SceneResolvedMaterialFrameSnapshot {
    let dynamic = SceneDynamicSnapshotResolver().resolve(
        frameIndex: index,
        generation: index,
        definitions: dynamicDefinitions,
        timelineValues: timelineValues
    )
    let result = SceneResolvedMaterialFrameSnapshot.validated(
        textureSnapshot: .init(
            frameEpoch: index,
            frameIndex: index,
            entries: textureEntries
        ),
        dynamicSnapshot: dynamic.snapshot,
        frameInputs: .init(
            frameIndex: index,
            screenSize: CGSize(width: width, height: height),
            sceneTime: sceneTime ?? Float(index),
            dayTime: 0,
            frameTime: 1 / 60,
            pointerCurrentNDC: .zero,
            pointerPreviousNDC: .zero
        )
    )
    guard case let .success(value) = result else {
        fatalError("frame snapshot failed")
    }
    return value
}

private enum ColorBlendMaskFixtureStatus: Equatable {
    case ready
    case pending
    case unavailable
    case wrongPurpose
    case wrongContent
    case samplingUnresolved
    case generationMismatch
    case requestIdentityMismatch
}

private func colorBlendMaskStatus(
    _ kind: ColorBlendMaskFixtureStatus,
    device: MTLDevice,
    generation: UInt64
) -> SceneFrameTextureLookupStatus {
    if kind == .pending { return .pending }
    if kind == .unavailable { return .unavailable }

    let purpose: SceneTextureLoadPurpose = kind == .wrongPurpose ? .noise : .mask
    let content: SceneTextureContent = kind == .wrongContent
        ? .color(.resolved(.straightAlpha)) : .data
    let candidateGeneration = generation
    let contentGeneration = kind == .generationMismatch
        ? generation + 1 : generation
    let requestIdentity: SceneFrameTextureIdentity = kind == .requestIdentityMismatch
        ? .asset(.init(
            path: SceneVFSAssetPath("textures/other-mask.tex")!,
            purpose: .mask
        ))
        : .asset(colorBlendMaskIdentity)
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .r8Unorm,
        width: 8,
        height: 4,
        mipmapped: true
    )
    descriptor.storageMode = .shared
    descriptor.usage = .shaderRead
    let texture = device.makeTexture(descriptor: descriptor)!
    for level in 0 ..< texture.mipmapLevelCount {
        let width = max(1, texture.width >> level)
        let height = max(1, texture.height >> level)
        let mappedWidth = max(1, width / 2)
        let bytes = (0 ..< width * height).map { index in
            index % width < mappedWidth ? UInt8(255) : UInt8(0)
        }
        texture.replace(
            region: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: level,
            withBytes: bytes,
            bytesPerRow: width
        )
    }
    let physicalSize = CGSize(width: texture.width, height: texture.height)
    let mappedSize = CGSize(width: 4, height: 4)
    let publication = SceneTextureProviderPublication(
        requestIdentity: requestIdentity,
        candidate: .init(
            texture: texture,
            identity: .provider(.video(
                layerID: layerID,
                lifecycleEpoch: generation
            )),
            generation: .provider(contentGeneration: candidateGeneration),
            purpose: purpose,
            content: content,
            physicalSize: physicalSize,
            mappedSize: mappedSize,
            uvTransform: .init(
                origin: .zero,
                xAxis: SIMD2(0.5, 0),
                yAxis: SIMD2(0, 1)
            ),
            sampling: kind == .samplingUnresolved
                ? .init(texFlags: 8) : .linearClamp,
            authoredFormat: .r8
        ),
        contentGeneration: contentGeneration
    )
    let resource = SceneFrameTextureResource(
        publication: publication,
        resourceGeneration: generation
    )
    switch kind {
    case .ready, .samplingUnresolved, .requestIdentityMismatch:
        return .ready(resource)
    case .wrongPurpose, .wrongContent, .generationMismatch:
        return .incomplete(.publication(
            publication,
            resourceGeneration: generation
        ))
    case .pending, .unavailable:
        fatalError("handled before publication construction")
    }
}

private enum SystemProviderFixtureStatus: Equatable {
    case ready
    case missing
    case absent
    case pending
    case unavailable
    case wrongPurpose
    case samplingUnresolved
    case incompleteContent
    case generationMismatch
    case requestIdentityMismatch
}

private func systemProviderTexture(
    _ device: MTLDevice,
    value: UInt8
) -> MTLTexture {
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .r8Unorm,
        width: 2,
        height: 2,
        mipmapped: true
    )
    descriptor.storageMode = .shared
    descriptor.usage = .shaderRead
    let texture = device.makeTexture(descriptor: descriptor)!
    for level in 0 ..< texture.mipmapLevelCount {
        let width = max(1, texture.width >> level)
        let height = max(1, texture.height >> level)
        let bytes = Array(repeating: value, count: width * height)
        texture.replace(
            region: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: level,
            withBytes: bytes,
            bytesPerRow: width
        )
    }
    return texture
}

private func systemProviderStatus(
    _ kind: SystemProviderFixtureStatus,
    device: MTLDevice,
    generation: UInt64
) -> SceneFrameTextureLookupStatus {
    if kind == .missing { fatalError("missing has no registry status") }
    if kind == .absent { return .absent }
    if kind == .pending { return .pending }
    if kind == .unavailable { return .unavailable }

    let requestIdentity: SceneFrameTextureIdentity =
        kind == .requestIdentityMismatch
        ? .system(.init(
            name: "$otherSystemProvider",
            purpose: .preservedChannels
        ))
        : .system(systemProviderIdentity)
    let purpose: SceneTextureLoadPurpose = kind == .wrongPurpose
        ? .noise : .preservedChannels
    let candidateGeneration = kind == .generationMismatch
        ? generation + 1 : generation
    let texture = systemProviderTexture(device, value: 0)
    let size = CGSize(width: texture.width, height: texture.height)
    let publication = SceneTextureProviderPublication(
        requestIdentity: requestIdentity,
        candidate: .init(
            texture: texture,
            identity: .provider(.mediaThumbnailCurrent),
            generation: .provider(contentGeneration: candidateGeneration),
            purpose: purpose,
            content: kind == .incompleteContent
                ? .color(.unresolved) : .data,
            physicalSize: size,
            mappedSize: size,
            uvTransform: .identity,
            sampling: kind == .samplingUnresolved
                ? .init(texFlags: 8) : .linearClamp,
            authoredFormat: .r8
        ),
        contentGeneration: generation
    )
    let resource = SceneFrameTextureResource(
        publication: publication,
        resourceGeneration: generation
    )
    return kind == .generationMismatch || kind == .incompleteContent
        ? .incomplete(.publication(
            publication,
            resourceGeneration: generation
        ))
        : .ready(resource)
}

private func systemProviderFallbackStatus(
    device: MTLDevice,
    generation: UInt64
) -> SceneFrameTextureLookupStatus {
    let texture = systemProviderTexture(device, value: 255)
    let size = CGSize(width: texture.width, height: texture.height)
    let publication = SceneTextureProviderPublication(
        requestIdentity: .asset(systemProviderFallbackIdentity),
        candidate: .init(
            texture: texture,
            identity: .provider(.video(
                layerID: layerID,
                lifecycleEpoch: generation
            )),
            generation: .provider(contentGeneration: generation),
            purpose: .preservedChannels,
            content: .data,
            physicalSize: size,
            mappedSize: size,
            uvTransform: .identity,
            sampling: .linearClamp,
            authoredFormat: .r8
        ),
        contentGeneration: generation
    )
    return .ready(.init(
        publication: publication,
        resourceGeneration: generation
    ))
}

private func clear(
    _ lease: SceneGraphRenderTargetLease,
    queue: MTLCommandQueue
) -> Bool {
    guard let buffer = queue.makeCommandBuffer() else { return false }
    for texture in lease.texturesByToken.values {
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = texture
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].storeAction = .store
        descriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 1, 1)
        guard let encoder = buffer.makeRenderCommandEncoder(
            descriptor: descriptor
        ) else { return false }
        encoder.endEncoding()
    }
    buffer.commit()
    buffer.waitUntilCompleted()
    return buffer.status == .completed && buffer.error == nil
}

private struct Readback {
    let buffer: MTLBuffer
    let bytesPerRow: Int
    let width: Int
    let height: Int

    var firstPixel: [UInt8] {
        let pointer = buffer.contents().assumingMemoryBound(to: UInt8.self)
        return Array(UnsafeBufferPointer(start: pointer, count: 4))
    }

    var lastPixel: [UInt8] {
        let offset = (height - 1) * bytesPerRow + (width - 1) * 4
        let pointer = buffer.contents().advanced(by: offset)
            .assumingMemoryBound(to: UInt8.self)
        return Array(UnsafeBufferPointer(start: pointer, count: 4))
    }

    func pixel(x: Int, y: Int) -> [UInt8] {
        let offset = y * bytesPerRow + x * 4
        let pointer = buffer.contents().advanced(by: offset)
            .assumingMemoryBound(to: UInt8.self)
        return Array(UnsafeBufferPointer(start: pointer, count: 4))
    }

    var allTexels: [[UInt8]] {
        (0 ..< height).flatMap { y in (0 ..< width).map { pixel(x: $0, y: y) } }
    }

    // Row-major bytes (width * 4 per row): pixel (x, y) spans bytes
    // [4x, 4x+4) of row y.
    var allPixels: [[UInt8]] {
        var rows: [[UInt8]] = []
        for y in 0 ..< height {
            let rowPointer = buffer.contents()
                .advanced(by: y * bytesPerRow)
                .assumingMemoryBound(to: UInt8.self)
            rows.append(Array(UnsafeBufferPointer(
                start: rowPointer,
                count: width * 4
            )))
        }
        return rows
    }
}

// D3 first slice: bounded lit base-capture scenarios on one claimed layer.
// The executor receives the per-request lit payload exactly as the frame
// preflight assembles it for an authored-lighting image material; every
// unlit contract must stay intact alongside the lit path.
