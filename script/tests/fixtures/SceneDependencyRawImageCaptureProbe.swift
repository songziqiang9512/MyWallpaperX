// Appended to the existing AtlasNamedProbe. The native runtime, candidates,
// registry, target pool and image capture pipeline remain production owners.
extension AtlasNamedProbe {
    static func samePreparedIdentity(
        _ prepared: SceneDependencyEffectInput?, _ actual: SceneDependencyEffectInput?
    ) -> Bool {
        guard let prepared, let actual else { return false }
        return prepared.consumerLayerID == actual.consumerLayerID
            && prepared.providerLayerID == actual.providerLayerID
            && prepared.variant == actual.variant && prepared.slot == actual.slot
            && prepared.blendMode == actual.blendMode
            && prepared.frameEpoch == actual.frameEpoch
            && prepared.texture === actual.texture
    }

    static func rawCaptureCandidate(
        _ source: MTLTexture, straight: Bool
    ) -> SceneTextureCandidate {
        .init(texture: source, identity: .builtIn(name: "own-raw-image"),
            generation: .immutable(revision: 1), purpose: straight ? .straightAlbedo : .premultipliedColor,
            content: .color(.resolved(straight ? .straightAlpha : .premultipliedAlpha)),
            physicalSize: CGSize(width: source.width, height: source.height),
            mappedSize: CGSize(width: source.width, height: source.height),
            uvTransform: .identity, sampling: .linearClamp)
    }

    static func rawCaptureSource(_ device: MTLDevice, straight: Bool) -> (MTLTexture, [UInt8]) {
        // Nonopaque input makes accidental association observable. These are
        // authored fixture bytes, not values calculated by a production helper.
        let bytes: [UInt8] = straight ? [64, 128, 200, 128] : [32, 64, 100, 128]
        let source = texture(device, 1, 1)
        bytes.withUnsafeBytes { source.replace(region: MTLRegionMake2D(0, 0, 1, 1),
            mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: 4) }
        return (source, bytes)
    }

    static func rawImageRepresentation(_ device: MTLDevice) -> [[String: Any]] {
        let queue = device.makeCommandQueue()!, pipeline = SceneImageLayerPipeline(device: device)!
        var rows: [[String: Any]] = []
        for graphFallback in [false, true] {
            for straight in [false, true] {
                let provider = SceneRenderDescriptor.Layer(id: 700, contentKind: "image",
                    utilityLayer: nil, alpha: 1, colorRGB: [1, 1, 1])
                let binding = SceneDependencyRenderPlan.Binding(consumerLayerID: 701,
                    providerLayerID: 700, slot: .init(effectID: "owned-raw", passIndex: 0, slotIndex: 1),
                    blendMode: 0, kind: graphFallback ? .visibleImageGraphOutput : .imageLayerBlend)
                let runtime = SceneDependencyFrameRuntime(descriptor: .init(layers: [provider],
                    bindings: [701: binding], graphOutputProviderLayerIDs: graphFallback ? [700] : []),
                    visibleLayerIDs: [700, 701], executableUtilityConsumerLayerIDs: [], device: device)
                let registry = SceneFrameTextureRegistry(), (source, expected) = rawCaptureSource(device, straight: straight)
                let candidate = rawCaptureCandidate(source, straight: straight)
                let epoch = registry.beginFrame(frameIndex: 1, layerSources: [:]), cb = queue.makeCommandBuffer()!
                var reason: String?
                let prepared = runtime.reserveEffectInput(for: binding, providerLayer: provider,
                    providerTexture: source, providerCandidate: candidate, layerMVP: matrix_identity_float4x4,
                    viewportSize: CGSize(width: 1, height: 1), frameEpoch: epoch, failureReason: &reason)
                let main = SceneMainPassEncoder(commandBuffer: cb, target: texture(device, 1, 1),
                    clearColor: MTLClearColorMake(0, 0, 0, 0), clearEnabled: true)
                let published = graphFallback
                    ? runtime.captureGraphSourceFallbackIfRequired(layer: provider, sourceTexture: source,
                        sourceCandidate: candidate, layerMVP: matrix_identity_float4x4,
                        viewportSize: CGSize(width: 1, height: 1), pipeline: pipeline,
                        textureRegistry: registry, mainPass: main)
                    : runtime.captureProviderIfRequired(layer: provider, sourceTexture: source,
                        sourceCandidate: candidate, layerMVP: matrix_identity_float4x4,
                        viewportSize: CGSize(width: 1, height: 1), pipeline: pipeline,
                        textureRegistry: registry, mainPass: main)
                let actual = runtime.effectInput(for: 701, textureRegistry: registry)
                let atom = registry.completeNamedLayerTargetResource(
                    reference: .init(providerLayerID: 700, variant: .primary), frameEpoch: epoch)
                let finished = main.finishEnsuringClear(), copied = prepared.map { readback(device, $0.texture, cb) }
                cb.commit(); cb.waitUntilCompleted(); registry.commitFramePublication()
                rows.append(["route": graphFallback ? "visible-image-raw-fallback" : "image-layer-blend",
                    "straight": straight, "published": status(published), "reserved": prepared != nil && reason == nil,
                    "preparedContentMatchesSource": prepared?.content == candidate.content,
                    "actualContentMatchesSource": actual?.content == candidate.content,
                    "preparedMatchesReadyIdentity": samePreparedIdentity(prepared, actual),
                    "preparedMatchesReadyContent": prepared?.content == actual?.content,
                    "publicationMatchesReadyContent": atom?.publication.candidate.content == actual?.content,
                    "distinctNamedTarget": prepared?.texture !== source && atom?.publication.texture === prepared?.texture,
                    "sourceUnchanged": read(source) == expected, "pixel": copied.map(read) ?? [], "expected": expected,
                    "completed": finished && cb.status == .completed && cb.error == nil])
            }
        }
        rows.append(rawImageAggregateRepresentation(device, queue: queue, pipeline: pipeline))
        return rows
    }

    static func rawImageAggregateRepresentation(
        _ device: MTLDevice, queue: MTLCommandQueue, pipeline: SceneImageLayerPipeline
    ) -> [String: Any] {
        // Preserve authored slot order rather than sorting the provider IDs.
        let providers = [801, 800].map { SceneRenderDescriptor.Layer(id: $0, contentKind: "image",
            utilityLayer: nil, alpha: 1, colorRGB: [1, 1, 1]) }
        let bindings = providers.enumerated().map { index, provider in
            SceneDependencyRenderPlan.Binding(consumerLayerID: 802, providerLayerID: provider.id,
                slot: .init(effectID: "owned-aggregate", passIndex: 0, slotIndex: index + 1),
                blendMode: 0, kind: .imageLayerBlend, requiresResolvedMaterialProgram: true)
        }
        let aggregate = SceneDependencyRenderPlan.MultiProviderAggregate(consumerLayerID: 802,
            bindings: bindings, authoredSlotOrder: bindings.map(\.slot))
        let runtime = SceneDependencyFrameRuntime(descriptor: .init(layers: providers,
            bindings: [:], graphOutputProviderLayerIDs: [], aggregates: [802: aggregate]),
            visibleLayerIDs: [800, 801, 802], executableUtilityConsumerLayerIDs: [], device: device)
        let registry = SceneFrameTextureRegistry(), epoch = registry.beginFrame(frameIndex: 1, layerSources: [:])
        let cb = queue.makeCommandBuffer()!, main = SceneMainPassEncoder(commandBuffer: cb,
            target: texture(device, 1, 1), clearColor: MTLClearColorMake(0, 0, 0, 0), clearEnabled: true)
        let inputs = [true, false].map { rawCaptureSource(device, straight: $0) }
        let candidates = inputs.enumerated().map { rawCaptureCandidate($0.element.0, straight: $0.offset == 0) }
        var reasons: [String?] = [], prepared: [SceneDependencyEffectInput?] = [], published: [String] = []
        for index in providers.indices {
            var reason: String?
            prepared.append(runtime.reserveEffectInput(for: bindings[index], providerLayer: providers[index],
                providerTexture: inputs[index].0, providerCandidate: candidates[index],
                layerMVP: matrix_identity_float4x4, viewportSize: CGSize(width: 1, height: 1),
                frameEpoch: epoch, failureReason: &reason))
            reasons.append(reason)
        }
        let unavailableBeforeCapture: Bool
        if case .unavailable = runtime.aggregateEffectInputResolution(for: aggregate, textureRegistry: registry) {
            unavailableBeforeCapture = true
        } else { unavailableBeforeCapture = false }
        for index in providers.indices {
            published.append(status(runtime.captureProviderIfRequired(layer: providers[index],
                sourceTexture: inputs[index].0, sourceCandidate: candidates[index],
                layerMVP: matrix_identity_float4x4, viewportSize: CGSize(width: 1, height: 1),
                pipeline: pipeline, textureRegistry: registry, mainPass: main)))
        }
        let actual: [SceneDependencyEffectInput]
        if case let .ready(values) = runtime.aggregateEffectInputResolution(for: aggregate, textureRegistry: registry) {
            actual = values
        } else { actual = [] }
        let ready = actual.count == 2
        let copied = prepared.compactMap { $0.map { readback(device, $0.texture, cb) } }
        let finished = main.finishEnsuringClear()
        cb.commit(); cb.waitUntilCompleted(); registry.commitFramePublication()
        return ["route": "mixed-raw-aggregate", "published": published.allSatisfy { $0 == "published" } ? "published" : published.joined(separator: ","),
            "reserved": prepared.allSatisfy { $0 != nil } && reasons.allSatisfy { $0 == nil },
            "unavailableBeforeCapture": unavailableBeforeCapture,
            "preparedContentMatchesSource": zip(prepared, candidates).allSatisfy { $0.0?.content == $0.1.content },
            "actualContentMatchesSource": ready && zip(actual, candidates).allSatisfy { $0.0.content == $0.1.content },
            "preparedMatchesReadyIdentity": ready && zip(prepared, actual).allSatisfy { samePreparedIdentity($0.0, $0.1) },
            "preparedMatchesReadyContent": ready && zip(prepared, actual).allSatisfy { $0.0?.content == $0.1.content },
            "slotOrderPreserved": actual.map(\.providerLayerID) == [801, 800] && actual.map { $0.slot.slotIndex } == [1, 2],
            "sourceUnchanged": inputs.allSatisfy { read($0.0) == $0.1 },
            "pixel": copied.flatMap(read), "expected": inputs.flatMap { $0.1 },
            "completed": finished && cb.status == .completed && cb.error == nil]
    }
}
