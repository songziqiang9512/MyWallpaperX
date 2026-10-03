@main
enum Harness {
    typealias Graph = SceneAuthoredEffectRenderPlan

    struct Fixture {
        let execution: SceneEffectStageExecutionPlan
        let framebufferIdentities: [Graph.TextureIdentity]
    }

    static func texture(
        _ kind: Graph.TextureKind,
        layerID: Int,
        effect: Graph.EffectKey? = nil,
        name: String? = nil
    ) -> Graph.TextureIdentity {
        .init(kind: kind, layerID: layerID, effect: effect, name: name)
    }

    static func binding(
        _ texture: Graph.TextureIdentity,
        slot: Int
    ) -> Graph.Binding {
        .init(
            slot: slot,
            authoredName: texture.name ?? "previous",
            texture: texture,
            conditions: nil
        )
    }

    static func node(
        index: Int,
        effect: Graph.EffectKey,
        ordinal: Int? = nil,
        target: Graph.TextureIdentity,
        reads: [(Int, Graph.TextureIdentity)],
        compose: SceneJSONValue? = nil
    ) -> Graph.Node {
        .init(
            nodeIndex: index,
            effect: effect,
            definitionPassIndex: index,
            materialOrdinal: ordinal ?? index,
            instancePassIndex: ordinal ?? index,
            kind: .material,
            materialPath: "materials/\(index).json",
            materialPassID: "materials/\(index).json#0",
            target: target,
            bindings: reads.map { binding($0.1, slot: $0.0) },
            commandSource: nil,
            commandTarget: nil,
            compose: compose,
            conditions: nil
        )
    }

    static func command(
        index: Int,
        effect: Graph.EffectKey,
        kind: Graph.NodeKind,
        source: Graph.TextureIdentity,
        target: Graph.TextureIdentity
    ) -> Graph.Node {
        .init(
            nodeIndex: index,
            effect: effect,
            definitionPassIndex: index,
            materialOrdinal: nil,
            instancePassIndex: nil,
            kind: kind,
            materialPath: nil,
            materialPassID: nil,
            target: nil,
            bindings: [],
            commandSource: source,
            commandTarget: target,
            compose: nil,
            conditions: nil
        )
    }

    static func fixture(
        effectIndex: Int,
        layerID: Int = 10,
        precise: Bool = false,
        framebufferNamePrefix: String = "",
        framebufferFormat: String = "rgba_backbuffer",
        framebufferScale: Double = 4,
        uniqueFirstTarget: Bool = false,
        clearFirstTarget: Bool = false,
        input authoredInput: Graph.TextureIdentity? = nil
    ) -> Fixture {
        let key = Graph.EffectKey(
            layerID: layerID,
            effectIndex: effectIndex,
            descriptorID: "\(layerID)#effect#\(effectIndex)"
        )
        let input = authoredInput ?? texture(.layerSource, layerID: layerID)
        let output = texture(.effectOutput, layerID: layerID, effect: key)
        let targets: [Graph.RenderTarget]
        let nodes: [Graph.Node]
        let identities: [Graph.TextureIdentity]

        if precise {
            let full = texture(.framebuffer, layerID: layerID, effect: key, name: "shared")
            identities = [full]
            targets = [.init(
                texture: full,
                extent: .init(kind: .input, first: nil, second: nil),
                format: "rgba_backbuffer",
                declaredUnique: false,
                clear: nil,
                uvs: nil,
                conditions: nil
            )]
            nodes = [
                node(index: 0, effect: key, target: full, reads: []),
                node(
                    index: 1,
                    effect: key,
                    target: output,
                    reads: [(0, full), (1, input)]
                ),
            ]
        } else {
            let quarterA = texture(
                .framebuffer,
                layerID: layerID,
                effect: key,
                name: "\(framebufferNamePrefix)sharedA"
            )
            let quarterB = texture(
                .framebuffer,
                layerID: layerID,
                effect: key,
                name: "\(framebufferNamePrefix)sharedB"
            )
            identities = [quarterA, quarterB]
            let scaled = Graph.TargetExtent(
                kind: .scale,
                first: framebufferScale,
                second: nil
            )
            targets = [quarterA, quarterB].enumerated().map { index, texture in
                .init(
                    texture: texture,
                    extent: scaled,
                    format: framebufferFormat,
                    declaredUnique: uniqueFirstTarget && index == 0,
                    clear: clearFirstTarget && index == 0
                        ? .array([.number(0), .number(0), .number(0), .number(0)])
                        : nil,
                    uvs: nil,
                    conditions: nil
                )
            }
            nodes = [
                node(index: 0, effect: key, target: quarterA, reads: [(0, input)]),
                node(index: 1, effect: key, target: quarterB, reads: [(0, quarterA)]),
                node(index: 2, effect: key, target: quarterA, reads: [(0, quarterB)]),
                node(
                    index: 3,
                    effect: key,
                    target: output,
                    reads: [(0, quarterA), (2, input)]
                ),
            ]
        }

        let graph = Graph(
            layerID: layerID,
            effects: [.init(
                key: key,
                definitionPath: precise
                    ? "effects/blurprecise/effect.json"
                    : "effects/blur/effect.json",
                input: input,
                output: output,
                nodeIndices: nodes.map(\.nodeIndex)
            )],
            renderTargets: targets,
            nodes: nodes,
            finalOutput: output,
            blockers: []
        )
        return Fixture(
            execution: .init(
                layerID: layerID,
                renderGraph: graph,
                materialNodeCount: nodes.count,
                logicalRenderTargetCount: targets.count,
                requiresExactInputExtent: precise,
                inputRole: input.kind == .layerSource
                    ? .layerSource
                    : .priorEffectOutput
            ),
            framebufferIdentities: identities
        )
    }

    static func directFixture(
        effectIndex: Int,
        layerID: Int = 10,
        precise: Bool = false,
        input authoredInput: Graph.TextureIdentity? = nil
    ) -> Fixture {
        let key = Graph.EffectKey(
            layerID: layerID,
            effectIndex: effectIndex,
            descriptorID: "\(layerID)#effect#\(effectIndex)"
        )
        let input = authoredInput ?? texture(.layerSource, layerID: layerID)
        let output = texture(.effectOutput, layerID: layerID, effect: key)
        let nodes = [node(index: 0, effect: key, target: output, reads: [(0, input)])]
        let graph = Graph(
            layerID: layerID,
            effects: [.init(
                key: key,
                definitionPath: "effects/direct/effect.json",
                input: input,
                output: output,
                nodeIndices: [0]
            )],
            renderTargets: [],
            nodes: nodes,
            finalOutput: output,
            blockers: []
        )
        return .init(
            execution: .init(
                layerID: layerID,
                renderGraph: graph,
                materialNodeCount: 1,
                logicalRenderTargetCount: 0,
                requiresExactInputExtent: precise,
                inputRole: input.kind == .layerSource
                    ? .layerSource
                    : .priorEffectOutput
            ),
            framebufferIdentities: []
        )
    }

    static func copyExtentFixture(
        layerID: Int,
        firstExtent: Graph.TargetExtent,
        secondExtent: Graph.TargetExtent
    ) -> Fixture {
        let key = Graph.EffectKey(
            layerID: layerID,
            effectIndex: 0,
            descriptorID: "\(layerID)#effect#copy-extent"
        )
        let input = texture(.layerSource, layerID: layerID)
        let output = texture(.effectOutput, layerID: layerID, effect: key)
        let half = texture(
            .framebuffer, layerID: layerID, effect: key, name: "half"
        )
        let full = texture(
            .framebuffer, layerID: layerID, effect: key, name: "full"
        )
        let targets: [Graph.RenderTarget] = [
            .init(
                texture: half,
                extent: firstExtent,
                format: "rgba_backbuffer",
                declaredUnique: true,
                clear: nil,
                uvs: nil,
                conditions: nil
            ),
            .init(
                texture: full,
                extent: secondExtent,
                format: "rgba_backbuffer",
                declaredUnique: false,
                clear: nil,
                uvs: nil,
                conditions: nil
            ),
        ]
        let nodes = [
            node(index: 0, effect: key, target: half, reads: [(0, input)]),
            command(index: 1, effect: key, kind: .copy, source: half, target: full),
            node(index: 2, effect: key, target: output, reads: [(0, full)]),
        ]
        let graph = Graph(
            layerID: layerID,
            effects: [.init(
                key: key,
                definitionPath: "effects/copy-extent/effect.json",
                input: input,
                output: output,
                nodeIndices: nodes.map(\.nodeIndex)
            )],
            renderTargets: targets,
            nodes: nodes,
            finalOutput: output,
            blockers: []
        )
        return .init(
            execution: .init(
                layerID: layerID,
                renderGraph: graph,
                materialNodeCount: 2,
                logicalRenderTargetCount: 2,
                requiresExactInputExtent: false,
                inputRole: .layerSource
            ),
            framebufferIdentities: [half, full]
        )
    }

    static func incompatibleCopyFixture(layerID: Int = 533) -> Fixture {
        copyExtentFixture(
            layerID: layerID,
            firstExtent: .init(kind: .scale, first: 2, second: nil),
            secondExtent: .init(kind: .scale, first: 1, second: nil)
        )
    }

    static func composeFixture(
        effectIndex: Int,
        composeCount: Int,
        input authoredInput: Graph.TextureIdentity? = nil
    ) -> Fixture {
        precondition(composeCount >= 0)
        let layerID = 10
        let key = Graph.EffectKey(
            layerID: layerID,
            effectIndex: effectIndex,
            descriptorID: "\(layerID)#effect#\(effectIndex)"
        )
        let input = authoredInput ?? texture(.layerSource, layerID: layerID)
        let output = texture(.effectOutput, layerID: layerID, effect: key)
        let nodes = (0...composeCount).map { index in
            node(
                index: index,
                effect: key,
                ordinal: index,
                target: output,
                reads: [(0, input)],
                compose: index < composeCount ? .bool(true) : nil
            )
        }
        let graph = Graph(
            layerID: layerID,
            effects: [.init(
                key: key,
                definitionPath: "effects/compose/effect.json",
                input: input,
                output: output,
                nodeIndices: nodes.map(\.nodeIndex)
            )],
            renderTargets: [],
            nodes: nodes,
            finalOutput: output,
            blockers: []
        )
        return .init(
            execution: .init(
                layerID: layerID,
                renderGraph: graph,
                materialNodeCount: nodes.count,
                logicalRenderTargetCount: 0,
                requiresExactInputExtent: false,
                inputRole: input.kind == .layerSource
                    ? .layerSource
                    : .priorEffectOutput
            ),
            framebufferIdentities: []
        )
    }

    static func historySwapFixture(
        effectIndex: Int,
        namePrefix: String = "",
        framebufferFormat: String = "rgba_backbuffer",
        extent: Graph.TargetExtent = .init(
            kind: .input,
            first: nil,
            second: nil
        )
    ) -> Fixture {
        let layerID = 10
        let key = Graph.EffectKey(
            layerID: layerID,
            effectIndex: effectIndex,
            descriptorID: "\(layerID)#effect#\(effectIndex)"
        )
        let input = texture(.layerSource, layerID: layerID)
        let output = texture(.effectOutput, layerID: layerID, effect: key)
        let history = texture(
            .framebuffer,
            layerID: layerID,
            effect: key,
            name: "\(namePrefix)history"
        )
        let scratch = texture(
            .framebuffer,
            layerID: layerID,
            effect: key,
            name: "\(namePrefix)scratch"
        )
        let targets = [
            Graph.RenderTarget(
                texture: history,
                extent: extent,
                format: framebufferFormat,
                declaredUnique: true,
                clear: nil,
                uvs: nil,
                conditions: nil
            ),
            Graph.RenderTarget(
                texture: scratch,
                extent: extent,
                format: framebufferFormat,
                declaredUnique: true,
                clear: nil,
                uvs: nil,
                conditions: nil
            ),
        ]
        let nodes = [
            node(index: 0, effect: key, target: scratch, reads: [(0, history)]),
            command(
                index: 1,
                effect: key,
                kind: .swap,
                source: history,
                target: scratch
            ),
            node(
                index: 2,
                effect: key,
                ordinal: 1,
                target: output,
                reads: [(0, history)]
            ),
        ]
        let graph = Graph(
            layerID: layerID,
            effects: [.init(
                key: key,
                definitionPath: "effects/history-swap/effect.json",
                input: input,
                output: output,
                nodeIndices: nodes.map(\.nodeIndex)
            )],
            renderTargets: targets,
            nodes: nodes,
            finalOutput: output,
            blockers: []
        )
        return .init(
            execution: .init(
                layerID: layerID,
                renderGraph: graph,
                materialNodeCount: 2,
                logicalRenderTargetCount: 2,
                requiresExactInputExtent: false,
                inputRole: .layerSource
            ),
            framebufferIdentities: [history, scratch]
        )
    }

    static func targetPlans(
        _ fixtures: [Fixture],
        width: Int,
        height: Int
    ) -> [SceneGraphRenderTargetPlan] {
        fixtures.enumerated().map { index, fixture in
            let result = SceneGraphRenderTargetPlan.make(
                graph: fixture.execution.renderGraph,
                inputRole: index == 0 ? .layerSource : .priorEffectOutput,
                inputWidth: width,
                inputHeight: height
            )
            switch result {
            case .success(let plan): return plan
            case .failure(let failure):
                fatalError("target plan fixture rejected: \(failure.rawValue)")
            }
        }
    }

    static func pairPlan(_ fixtures: [Fixture]) -> SceneLayerFullFramePairPlan {
        switch SceneLayerFullFramePairPlan.make(
            conditionPrunedGraphs: fixtures.map { $0.execution.renderGraph }
        ) {
        case .success(let plan): return plan
        case .failure(let failure):
            fatalError("pair plan fixture rejected: \(failure.rawValue)")
        }
    }

    static func admittedGraphs(_ fixtures: [Fixture]) -> [Graph] {
        fixtures.map { $0.execution.renderGraph }
    }

    static func clear(
        _ texture: MTLTexture,
        color: MTLClearColor,
        device: MTLDevice
    ) -> Bool {
        guard let queue = device.makeCommandQueue(),
              let commandBuffer = queue.makeCommandBuffer() else { return false }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = color
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else {
            return false
        }
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        return commandBuffer.status == .completed
    }

    static func pixel(_ texture: MTLTexture, device: MTLDevice) -> [UInt8]? {
        guard let queue = device.makeCommandQueue(),
              let commandBuffer = queue.makeCommandBuffer(),
              let readback = device.makeBuffer(length: 4, options: .storageModeShared),
              let encoder = commandBuffer.makeBlitCommandEncoder() else { return nil }
        encoder.copy(
            from: texture,
            sourceSlice: 0,
            sourceLevel: 0,
            sourceOrigin: .init(x: 0, y: 0, z: 0),
            sourceSize: .init(width: 1, height: 1, depth: 1),
            to: readback,
            destinationOffset: 0,
            destinationBytesPerRow: 4,
            destinationBytesPerImage: 4
        )
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed else { return nil }
        return Array(UnsafeBufferPointer(
            start: readback.contents().assumingMemoryBound(to: UInt8.self),
            count: 4
        ))
    }

    static func physicalObjects(
        _ prepared: ScenePreparedPersistentGraphTargets
    ) -> Set<ObjectIdentifier> {
        Set(prepared.leases.flatMap {
            $0.texturesByToken.values.map(ObjectIdentifier.init)
        })
    }

    static func completedOrderedAllocation(
        allocator: ScenePersistentGraphTargetAllocator,
        plan: SceneLayerGraphTargetPlan,
        queue: MTLCommandQueue
    ) -> (
        prepared: ScenePreparedPersistentGraphTargets,
        commit: ScenePreparedPersistentGraphTargets.Commit,
        commandBuffer: MTLCommandBuffer
    )? {
        guard let commandBuffer = queue.makeCommandBuffer(),
              let prepared = allocator.prepare(
                  plan: plan,
                  orderingContext: .init(commandBuffer: commandBuffer)
              ), let commit = prepared.commitAndPin(
                  historyTokensByEffect: [:],
                  commandBuffer: commandBuffer
              ) else { return nil }
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status != .notEnqueued else { return nil }
        return (prepared, commit, commandBuffer)
    }

    static func formatAccounting(_ device: MTLDevice) -> [String: Bool] {
        var checks: [String: Bool] = [:]
        for (formatName, format, pixelFormat, pixelBytes) in [
            ("sdr", SceneGraphRenderTargetPlan.TextureFormat.rgbaBackbuffer, MTLPixelFormat.bgra8Unorm, 4),
            ("hdr", .rgba16f, .rgba16Float, 8),
        ] {
            for (width, height) in [(64, 32), (32, 96)] {
                let pixels = width * height
                let cases: [(String, Fixture, Int, Int)] = [
                    ("direct", directFixture(effectIndex: 910), 0, 0),
                    ("r8", fixture(effectIndex: 911, framebufferFormat: "r8"), pixels / 8, 0),
                    ("history", historySwapFixture(effectIndex: 912, framebufferFormat: "rgba8888"), pixels * 8, pixels * 8),
                ]
                for (name, value, privateBytes, historyBytes) in cases {
                    guard case .success(let target) = SceneGraphRenderTargetPlan.make(
                        graph: value.execution.renderGraph, inputRole: .layerSource,
                        inputWidth: width, inputHeight: height, backbufferFormat: format
                    ) else { fatalError("format accounting target rejected") }
                    for storage in [SceneLayerGraphTargetPlan.FullFramePairStorage.owned, .shared] {
                        let expected = privateBytes + (storage == .owned ? pixels * pixelBytes * 2 : 0)
                        let key = "\(formatName)-\(width)x\(height)-\(name)-\(storage)"
                        let exact = SceneLayerGraphTargetPlan.make(
                            plans: [target], pairPlan: pairPlan([value]), byteBudget: expected,
                            pairStorage: storage
                        )
                        if case .success(let plan) = exact {
                            checks[key] = plan.residentByteCost == expected
                                && plan.historyByteCost == historyBytes
                        } else { checks[key] = false }
                        if expected > 0 {
                            let short = SceneLayerGraphTargetPlan.make(
                                plans: [target], pairPlan: pairPlan([value]), byteBudget: expected - 1,
                                pairStorage: storage
                            )
                            if case .failure(.byteBudgetExceeded) = short {
                                checks[key + "-short"] = true
                            } else { checks[key + "-short"] = false }
                        }
                    }
                }
            }
            let overflowFixture = directFixture(effectIndex: 913)
            guard case .success(let overflowTarget) = SceneGraphRenderTargetPlan.make(
                graph: overflowFixture.execution.renderGraph, inputRole: .layerSource,
                inputWidth: Int.max, inputHeight: 2, backbufferFormat: format
            ) else { fatalError("overflow value fixture rejected before cost owner") }
            if case .failure(.byteCostOverflow) = SceneLayerGraphTargetPlan.make(
                plans: [overflowTarget], pairPlan: pairPlan([overflowFixture]),
                byteBudget: Int.max, pairStorage: .owned
            ) { checks[formatName + "-overflow"] = true }
            else { checks[formatName + "-overflow"] = false }
            // API-boundary injection: a shared graph owns no pair bytes, while the
            // real shared-pair allocation owner must reject overflow before allocating.
            if case .success(let noPrivateSlots) = SceneLayerGraphTargetPlan.make(
                plans: [overflowTarget], pairPlan: pairPlan([overflowFixture]),
                byteBudget: 0, pairStorage: .shared
            ) { checks[formatName + "-shared-overflow-private-zero"] = noPrivateSlots.residentByteCost == 0 }
            else { checks[formatName + "-shared-overflow-private-zero"] = false }
            let overflowPool = SceneOffscreenTexturePool(device: device, pixelFormat: pixelFormat)
            var overflowFactoryCalls = 0
            let impossiblePair = overflowPool.sharedPairCandidate(width: Int.max, height: 2) { _, _ in
                overflowFactoryCalls += 1
                return nil
            }
            checks[formatName + "-shared-overflow-allocation-refused"] = impossiblePair == nil
                && overflowFactoryCalls == 0 && overflowPool.residentByteCost == 0
                && overflowPool.pendingSharedPairByteCosts(for: [.sharedGraphPair(width: Int.max, height: 2)]) == nil
            // Two distinct graphs, one physical pair, and two private R8 FBOs per graph.
            // The two sizes exercise independent cache keys without modifying pool policy.
            for dimensions in [[(64, 32), (64, 32)], [(64, 32), (32, 96)]] {
                let identical = dimensions[0] == dimensions[1]
                let label = formatName + (identical ? "-same-size-pool" : "-different-size-pool")
                let pairPixels = identical ? 64 * 32 : 64 * 32 + 32 * 96
                let expected = pairPixels * pixelBytes * 2
                    + dimensions.reduce(0) { $0 + $1.0 * $1.1 / 8 }
                for budget in [expected, expected - 1] {
                    let pool = SceneOffscreenTexturePool(device: device, pixelFormat: pixelFormat, residentByteBudget: budget)
                    guard let queue = device.makeCommandQueue(), let buffer = queue.makeCommandBuffer() else {
                        fatalError("format accounting command buffer unavailable")
                    }
                    let values = dimensions.indices.map { fixture(effectIndex: 920 + $0, layerID: 920 + $0, framebufferFormat: "r8") }
                    let plans = values.enumerated().compactMap { index, value in
                        pool.framePlanForPersistentGraphTargets(
                            admittedGraphs: admittedGraphs([value]), pairPlan: pairPlan([value]),
                            requestedWidth: dimensions[index].0, requestedHeight: dimensions[index].1,
                            usesSharedFullFrameWorkingPair: true, orderingContext: .init(commandBuffer: buffer)
                        )
                    }
                    guard plans.count == 2 else { fatalError("format pool plan unavailable") }
                    if budget < expected {
                        checks[label + "-short"] = pool.preflightPersistentGraphTargets(plans)
                            == .rejected(reasonCode: "frame-target-byte-budget-exceeded")
                            && pool.residentByteCost == 0 && pool.residentTextureCount == 0
                        continue
                    }
                    guard pool.preflightPersistentGraphTargets(plans) == .ready,
                          let prepared = pool.preparePersistentGraphTargets(framePlans: plans),
                          let commits = pool.commitAndPinPersistentGraphTargets(
                              prepared, historyTokensByTarget: [[:], [:]], commandBuffer: buffer
                          ) else { checks[label] = false; continue }
                    let pairs = prepared.map { value in
                        Set(value.leases.flatMap { [ObjectIdentifier($0.table.fullFramePair.first), ObjectIdentifier($0.table.fullFramePair.second)] })
                    }
                    let allTextures = prepared.flatMap { $0.leases.flatMap { Array($0.texturesByToken.values) } }
                    var unique: [ObjectIdentifier: MTLTexture] = [:]
                    for texture in allTextures { unique[ObjectIdentifier(texture)] = texture }
                    let actualBytes = unique.values.reduce(0) { result, texture in
                        result + texture.width * texture.height * (texture.pixelFormat == .r8Unorm ? 1 : pixelBytes)
                    }
                    checks[label] = pool.residentByteCost == expected && actualBytes == expected
                        && (identical ? pairs[0] == pairs[1] : pairs[0].isDisjoint(with: pairs[1]))
                        && unique.count == (identical ? 6 : 8)
                    buffer.commit()
                    buffer.waitUntilCompleted()
                    checks[label + "-completed"] = buffer.status == .completed
                    commits.forEach { $0.releaseAll() }
                    guard let next = queue.makeCommandBuffer() else { fatalError("next buffer") }
                    let nextPlans = values.enumerated().compactMap { index, value in
                        pool.framePlanForPersistentGraphTargets(
                            admittedGraphs: admittedGraphs([value]), pairPlan: pairPlan([value]),
                            requestedWidth: dimensions[index].0, requestedHeight: dimensions[index].1,
                            usesSharedFullFrameWorkingPair: true, orderingContext: .init(commandBuffer: next)
                        )
                    }
                    guard let nextPrepared = pool.preparePersistentGraphTargets(framePlans: nextPlans),
                          let nextCommits = pool.commitAndPinPersistentGraphTargets(
                              nextPrepared, historyTokensByTarget: [[:], [:]], commandBuffer: next
                          ) else { checks[label + "-next-frame"] = false; continue }
                    checks[label + "-next-frame"] = nextPrepared.enumerated().allSatisfy { index, value in
                        Set(value.leases.flatMap { [ObjectIdentifier($0.table.fullFramePair.first), ObjectIdentifier($0.table.fullFramePair.second)] }) == pairs[index]
                    } && pool.residentByteCost == expected
                    for value in nextPrepared {
                        let pass = MTLRenderPassDescriptor()
                        pass.colorAttachments[0].texture = value.leases.first?.table.fullFramePair.first
                        pass.colorAttachments[0].loadAction = .clear
                        pass.colorAttachments[0].storeAction = .store
                        pass.colorAttachments[0].clearColor = MTLClearColorMake(0.25, 0.5, 0, 1)
                        guard let encoder = next.makeRenderCommandEncoder(descriptor: pass) else {
                            fatalError("next-frame clear")
                        }
                        encoder.endEncoding()
                    }
                    next.commit()
                    next.waitUntilCompleted()
                    checks[label + "-next-frame-completed"] = next.status == .completed
                    nextCommits.forEach { $0.releaseAll() }
                    pool.reset()
                    checks[label + "-released"] = pool.residentByteCost == 0
                }
            }
        }
        return checks
    }


    static func reflectionResidency(_ device: MTLDevice) -> [String: Bool] {
        let queue = device.makeCommandQueue()!
        var checks: [String: Bool] = [:]
        // Independent NPOT costs: (13*7 + 6*3 + 3*1 + 1*1) texels.
        for (format, bytes) in [(MTLPixelFormat.rgba8Unorm, 4), (.rgba16Float, 8)] {
            let total = 113 * bytes
            let short = SceneOffscreenTexturePool(device: device, pixelFormat: format, residentByteBudget: total - 1)
            var calls = 0
            let denied = short.reserveEnvironment(width: 13, height: 7, commandBuffer: queue.makeCommandBuffer()!, textureFactory: {
                calls += 1; return device.makeTexture(descriptor: $0)
            })
            checks["npot-short-\(bytes)"] = denied == nil && calls == 0 && short.residentByteCost == 0
            let exact = SceneOffscreenTexturePool(device: device, pixelFormat: format, residentByteBudget: total)
            let cb = queue.makeCommandBuffer()!
            let first = exact.reserveEnvironment(width: 13, height: 7, commandBuffer: cb)!
            let same = exact.reserveEnvironment(width: 13, height: 7, commandBuffer: cb)!
            checks["npot-exact-\(bytes)"] = first.texture.mipmapLevelCount == 4 && exact.residentByteCost == total
            checks["same-cb-reuses-\(bytes)"] = first.texture === same.texture && first.pin.generation == same.pin.generation
            checks["other-cb-blocked-\(bytes)"] = exact.reserveEnvironment(width: 13, height: 7, commandBuffer: queue.makeCommandBuffer()!) == nil
            exact.reset()
            checks["reset-retains-pinned-\(bytes)"] = exact.residentByteCost == total
            first.pin.release()
            checks["other-pin-retains-\(bytes)"] = exact.residentByteCost == total
            same.pin.release()
            checks["cancel-releases-\(bytes)"] = exact.residentByteCost == 0
        }
        // A late actual factory nil permits one legal idle reclamation and
        // retry. Already allocated prefixes remain the objects published on
        // success; a failed retry never publishes any successful prefix.
        for failure in 1...3 {
            let pool = SceneOffscreenTexturePool(device: device, residentByteBudget: 512)
            _ = pool.compositionTarget(width: 8, height: 8, commandBuffer: nil)!
            let revision = pool.allocationCache.revision
            let cb = queue.makeCommandBuffer()!
            var calls = 0
            var attempts: [String: Int] = [:]
            var created: [String: MTLTexture] = [:]
            let result = pool.reserveCompositionTargets(dimensions: [(4,4),(6,6),(7,7)], commandBuffer: cb, textureFactory: { descriptor in
                calls += 1
                let extent = "\(descriptor.width)x\(descriptor.height)"
                attempts[extent, default: 0] += 1
                if calls == failure { return nil }
                let texture = device.makeTexture(descriptor: descriptor)
                created[extent] = texture
                return texture
            })
            let recovered = result?.count == 3 && calls == 4
                && attempts.values.sorted() == [1, 1, 2]
                && result?.allSatisfy { lease in
                    created["\(lease.texture.width)x\(lease.texture.height)"] === lease.texture
                } == true
                && pool.residentAllocationCount == 3 && pool.residentByteCost == 404
                && pool.allocationCache.revision != revision
                && pool.allocationCache.locked {
                    pool.allocationCache.residents[.current(.composition(width: 8, height: 8))] == nil
                }
            result?.forEach { $0.pin.release() }
            pool.reset()

            let failed = SceneOffscreenTexturePool(device: device, residentByteBudget: 512)
            _ = failed.compositionTarget(width: 8, height: 8, commandBuffer: nil)!
            let failedRevision = failed.allocationCache.revision
            var failedCalls = 0
            let rejected = failed.reserveCompositionTargets(dimensions: [(4,4),(6,6),(7,7)], commandBuffer: queue.makeCommandBuffer()!, textureFactory: { descriptor in
                failedCalls += 1
                if failedCalls == failure || failedCalls == failure + 1 { return nil }
                return device.makeTexture(descriptor: descriptor)
            })
            checks["nth-allocation-recovers-once-\(failure)"] = recovered
                && pool.residentByteCost == 0
                && rejected == nil && failedCalls == failure + 1
                && failed.residentAllocationCount == 0 && failed.residentByteCost == 0
                && failed.allocationCache.revision != failedRevision
        }
        let raced = SceneOffscreenTexturePool(device: device, residentByteBudget: 1024)
        _ = raced.compositionTarget(width: 8, height: 8, commandBuffer: nil)
        var callsAfterReset = 0
        var resetRevision = raced.allocationCache.revision
        let aborted = raced.reserveCompositionTargets(dimensions: [(4,4),(6,6)], commandBuffer: queue.makeCommandBuffer()!, textureFactory: { descriptor in
            callsAfterReset += 1
            let texture = device.makeTexture(descriptor: descriptor)
            if callsAfterReset == 1 { raced.reset(); resetRevision = raced.allocationCache.revision }
            return texture
        })
        checks["reset-during-allocation-aborts-whole-stage"] = aborted == nil && callsAfterReset == 2
            && raced.residentAllocationCount == 0 && raced.residentByteCost == 0
            && raced.allocationCache.revision == resetRevision
        let pool = SceneOffscreenTexturePool(device: device, pixelFormat: .rgba16Float, residentByteBudget: 896)
        let cb = queue.makeCommandBuffer()!
        let mandatory = pool.reserveCompositionTargets(dimensions: [(8,8),(4,4),(4,4)], commandBuffer: cb)!
        let display = mandatory.first { $0.texture.width == 8 }!.texture
        checks["mandatory-deduplicates"] = mandatory.count == 2 && pool.residentByteCost == 640
        let revision = pool.allocationCache.revision
        checks["optional-cannot-steal-display"] = pool.reserveEnvironment(width: 8, height: 8, commandBuffer: cb) == nil
            && pool.residentByteCost == 640 && pool.allocationCache.revision == revision
            && pool.compositionTarget(width: 8, height: 8, commandBuffer: cb)!.texture === display
        mandatory.forEach { $0.pin.release() }
        pool.reset()
        checks["mandatory-cancel-releases"] = pool.residentByteCost == 0
        // Actual GPU work retains an old generation across reset and replacement.
        let lifecycle = SceneOffscreenTexturePool(device: device, pixelFormat: .rgba16Float, residentByteBudget: 4096)
        let oldCB = queue.makeCommandBuffer()!
        let old = lifecycle.reserveEnvironment(width: 13, height: 7, commandBuffer: oldCB)!
        let render = MTLRenderPassDescriptor()
        render.colorAttachments[0].texture = old.texture
        render.colorAttachments[0].loadAction = .clear; render.colorAttachments[0].storeAction = .store
        render.colorAttachments[0].clearColor = MTLClearColorMake(0.25, 0.5, 0.75, 1)
        oldCB.makeRenderCommandEncoder(descriptor: render)!.endEncoding()
        let blit = oldCB.makeBlitCommandEncoder()!; blit.generateMipmaps(for: old.texture); blit.endEncoding()
        lifecycle.reset()
        let nextCB = queue.makeCommandBuffer()!
        let next = lifecycle.reserveEnvironment(width: 7, height: 5, commandBuffer: nextCB)!
        checks["resize-retains-old-generation"] = old.texture !== next.texture && old.pin.generation != next.pin.generation
            && lifecycle.residentByteCost == (113 + 35 + 6 + 1) * 8
        let finished = DispatchSemaphore(value: 0)
        oldCB.addCompletedHandler { _ in old.pin.release(); finished.signal() }
        oldCB.commit(); oldCB.waitUntilCompleted(); finished.wait()
        checks["gpu-completion-releases-old"] = oldCB.status == .completed && oldCB.error == nil && lifecycle.residentByteCost == 42 * 8
        next.pin.release(); lifecycle.reset()
        checks["next-cancel-releases"] = lifecycle.residentByteCost == 0

        // Reflection A -> ordinary B -> reflection C share the same scratch
        // owner. B is held on a real GPU event while C requests that extent.
        let interleaved = SceneOffscreenTexturePool(device: device, residentByteBudget: 512)
        let frameA = queue.makeCommandBuffer()!
        let reservedA = interleaved.reserveCompositionTargets(dimensions: [(8,8)], commandBuffer: frameA)!.first!
        let frameB = queue.makeCommandBuffer()!, event = device.makeSharedEvent()!
        frameB.encodeWaitForEvent(event, value: 1)
        let ordinary = interleaved.compositionTarget(width: 8, height: 8, commandBuffer: frameB)!
        let root = SceneMainPassEncoder(commandBuffer: frameB, target: ordinary.texture,
            clearColor: MTLClearColorMake(0,1,0,1), clearEnabled: true)
        let child = SceneMainPassEncoder(commandBuffer: frameB, target: ordinary.texture,
            clearColor: MTLClearColorMake(0,0,0,0), clearEnabled: false, submissionOwner: root)
        child.retainCompositionPin(ordinary.pin)
        precondition(root.finishEnsuringClear()); root.armCompositionPins()
        let completedB = DispatchSemaphore(value: 0)
        frameB.addCompletedHandler { _ in completedB.signal() }; frameB.commit()
        let frameC = queue.makeCommandBuffer()!
        checks["ordinary-between-reflections-keeps-pin"] = ordinary.texture !== reservedA.texture
            && interleaved.reserveCompositionTargets(dimensions: [(8,8)], commandBuffer: frameC) == nil
            && interleaved.residentByteCost == 512
        reservedA.pin.release()
        let reservedC = interleaved.reserveCompositionTargets(dimensions: [(8,8)], commandBuffer: frameC)!.first!
        checks["pending-ordinary-never-reused"] = reservedC.texture !== ordinary.texture
            && interleaved.residentByteCost == 512
        event.signaledValue = 1; frameB.waitUntilCompleted(); completedB.wait()
        checks["ordinary-completion-retires-generation"] = frameB.status == .completed && frameB.error == nil
            && interleaved.residentByteCost == 256
        reservedC.pin.release(); interleaved.reset()
        checks["interleaved-cancel-releases"] = interleaved.residentByteCost == 0
        return checks
    }

    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("{\"metalUnavailable\":true}")
            return
        }
        var result: [String: Any] = [:]
        func append(_ checks: [String: Any]) {
            result.merge(checks) { _, _ in fatalError("duplicate pool result key") }
        }
        let budget = budgetPolicyChecks(device)
        append(budget.checks)
        append(copyExtentChecks(device))
        append(sampleBudgetChecks(device,
            automaticBudgetFloor: budget.automaticBudgetFloor,
            defaultBudgetPool: budget.defaultBudgetPool,
            explicit128Pool: budget.explicit128Pool))
        append(sharedFramebufferChecks(device))
        append(singleChannelChecks(device))
        let chain = directChainChecks(device)
        append(chain.checks)
        let slots = inFlightSlotChecks(device,
            directFixtures: chain.directFixtures, directPairPlan: chain.directPairPlan)
        append(slots.checks)
        append(queueOrderingChecks(device,
            inflightPlan: slots.inflightPlan, orderedQueue: slots.orderedQueue))
        append(residencyPressureChecks(device,
            inflightPlan: slots.inflightPlan, inflightSlotCount: slots.inflightSlotCount))
        let inFlightHistory = inFlightHistoryChecks(device)
        append(inFlightHistory.checks)
        append(orderedHistoryChecks(device,
            orderedQueue: slots.orderedQueue,
            inflightHistoryPlan: inFlightHistory.inflightHistoryPlan,
            inflightHistoryCache: inFlightHistory.inflightHistoryCache,
            inflightHistoryEffect: inFlightHistory.inflightHistoryEffect,
            inflightHistoryCommit1: inFlightHistory.inflightHistoryCommit1,
            inflightHistoryCommit2: inFlightHistory.inflightHistoryCommit2,
            inflightHistoryCommit3: inFlightHistory.inflightHistoryCommit3))
        append(planIdentityChecks(device, defaultBudget: chain.defaultBudget))
        let history = historyFailureChecks(device)
        append(history.checks)
        append(historyResizeChecks(device))
        append(batchCommitChecks(device, directBudgetPool: chain.directBudgetPool))
        append(pairMappingChecks(device,
            rotationPool: chain.rotationPool, directPairPlan: chain.directPairPlan,
            directGraphs: chain.directGraphs, historyFixture: history.historyFixture,
            historyLease1: history.historyLease1))
        append(composeMappingChecks(device))
        append([
            "metalUnavailable": false,
            "formatAccounting": formatAccounting(device),
            "reflectionResidency": reflectionResidency(device),
            "standardMaximumDimension": SceneOffscreenResolutionPolicy.maximumDimension(
                hardLimit: 4096, includesAuthoredShader: false
            ),
            "authoredShaderMaximumDimension": SceneOffscreenResolutionPolicy.maximumDimension(
                hardLimit: 4096, includesAuthoredShader: true
            ),
        ])
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
