import CoreGraphics
import Foundation
import Metal

final class SceneDynamicTextTextureStore: @unchecked Sendable {
    struct Snapshot {
        let layerSources: [Int: SceneLayerSourcePublication]
    }

    private let cacheDirectory: URL
    private let device: MTLDevice
    private let authoredLayerIDs: Set<Int>
    private var layersByID: [Int: SceneRenderDescriptor.Layer]
    private let queue = DispatchQueue(label: "com.mywallpaperx.scene.dynamic-text", qos: .userInitiated)
    private let lock = NSLock()
    private var generationState = SceneDynamicTextGenerationState()
    private var currentTextures: [Int: MTLTexture]
    private var currentRenderSizes: [Int: [Float]]
#if DEBUG
    private var debugLoggedDynamicLayers: Set<Int> = []
#endif

    init(
        descriptor: SceneRenderDescriptor,
        cacheDirectory: URL,
        device: MTLDevice,
        initialTextures: [Int: MTLTexture]
    ) {
        let visibleIDs = SceneLayerVisibility.visibleLayerIDs(in: descriptor)
        let layers = descriptor.layers.filter {
            $0.contentKind == "text"
                && $0.text != nil
                && $0.textStyle != nil
                && visibleIDs.contains($0.id)
        }
        self.cacheDirectory = cacheDirectory
        self.device = device
        self.layersByID = Dictionary(uniqueKeysWithValues: layers.map { ($0.id, $0) })
        authoredLayerIDs = Set(layers.map(\.id))
        self.currentTextures = initialTextures
        self.currentRenderSizes = Dictionary(uniqueKeysWithValues: layers.compactMap { layer in
            layer.renderSizeWH.map { (layer.id, $0) }
        })
        for layer in layers {
            generationState.registerInitial(
                layerID: layer.id,
                signature: Self.signature(for: layer, snapshot: nil),
                isReady: initialTextures[layer.id] != nil
            )
        }
    }

    func update(
        from snapshot: SceneDynamicSnapshot,
        dynamicLayers: [SceneRenderDescriptor.Layer] = []
    ) {
        let admittedDynamic = dynamicLayers.filter {
            $0.contentKind == "text" && $0.text != nil && $0.textStyle != nil
        }
        let admittedIDs = Set(admittedDynamic.map(\.id))
        lock.lock()
        let retired = Set(layersByID.keys).subtracting(authoredLayerIDs).subtracting(admittedIDs)
        for layerID in retired {
            layersByID.removeValue(forKey: layerID)
            currentTextures.removeValue(forKey: layerID)
            currentRenderSizes.removeValue(forKey: layerID)
            generationState.unregister(layerID: layerID)
        }
        for layer in admittedDynamic {
            if layersByID[layer.id] == nil {
                layersByID[layer.id] = layer
                let signature = Self.signature(for: layer, snapshot: nil)
                if let request = generationState.registerDynamic(
                    layerID: layer.id, signature: signature
                ) {
                    lock.unlock()
                    schedule(request)
                    lock.lock()
                }
            } else {
                layersByID[layer.id] = layer
            }
        }
        let layers = Array(layersByID.values)
        lock.unlock()
        for layer in layers {
            let signature = Self.signature(for: layer, snapshot: snapshot)
            lock.lock()
            let request = generationState.schedule(layerID: layer.id, signature: signature)
            lock.unlock()
            if let request { schedule(request) }
        }
    }

    func snapshot() -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        let pairs: [(Int, SceneLayerSourcePublication)] = currentTextures.compactMap {
            layerID, texture in
            guard let generation = generationState.readyGeneration(layerID: layerID),
                  let renderSizeWH = currentRenderSizes[layerID] else {
                return nil
            }
            let size = CGSize(width: texture.width, height: texture.height)
            let publication = SceneTextureProviderPublication(
                requestIdentity: .layerSource(layerID),
                candidate: SceneTextureCandidate(
                    texture: texture,
                    identity: .provider(.dynamicText(layerID: layerID)),
                    generation: .provider(contentGeneration: generation),
                    purpose: .premultipliedColor,
                    content: .color(.resolved(.premultipliedAlpha)),
                    physicalSize: size,
                    mappedSize: size,
                    uvTransform: .identity,
                    sampling: .linearClamp,
                ),
                contentGeneration: generation
            )
            guard let layerSource = SceneLayerSourcePublication(
                layerID: layerID,
                publication: publication,
                renderSizeWH: renderSizeWH
            ) else { return nil }
            return (layerID, layerSource)
        }
        let layerSources = Dictionary(uniqueKeysWithValues: pairs)
        return Snapshot(layerSources: layerSources)
    }

    deinit {
        lock.lock()
        generationState.reset()
        lock.unlock()
    }

    private func schedule(_ request: SceneDynamicTextGenerationState.RenderRequest) {
        queue.async { [weak self] in self?.render(request) }
    }

    private func render(_ request: SceneDynamicTextGenerationState.RenderRequest) {
        lock.lock()
        let layer = layersByID[request.layerID]
        lock.unlock()
        guard let layer else { return }
        let rendered = SceneTextTextureLoader.makeDynamicTexture(
            for: layer,
            content: request.signature.content,
            pointSize: request.signature.pointSize,
            colorRGB: request.signature.colorRGB,
            maxWidth: request.signature.maxWidth,
            cacheDirectory: cacheDirectory,
            device: device
        )
#if DEBUG
        var debugPublication: (
            layerID: Int,
            generation: UInt64,
            pointSize: Float,
            maxWidth: Float,
            logicalWidth: Float,
            logicalHeight: Float,
            textureWidth: Int,
            textureHeight: Int
        )?
#endif
        lock.lock()
        let completion = generationState.finish(request, succeeded: rendered != nil)
        if completion.accepted, let rendered {
            currentTextures[request.layerID] = rendered.texture
            currentRenderSizes[request.layerID] = rendered.renderSizeWH
#if DEBUG
            if debugLoggedDynamicLayers.insert(request.layerID).inserted {
                debugPublication = (
                    request.layerID,
                    request.generation,
                    request.signature.pointSize,
                    request.signature.maxWidth,
                    rendered.renderSizeWH[0],
                    rendered.renderSizeWH[1],
                    rendered.texture.width,
                    rendered.texture.height
                )
            }
#endif
        }
        lock.unlock()
#if DEBUG
        if let debugPublication {
            NSLog(
                "MWX DEBUG SCENE: phase=dynamic-text-published layer=%d generation=%llu pointSize=%.3f maxWidth=%.3f logicalSize=%.3fx%.3f textureSize=%dx%d",
                debugPublication.layerID,
                debugPublication.generation,
                debugPublication.pointSize,
                debugPublication.maxWidth,
                debugPublication.logicalWidth,
                debugPublication.logicalHeight,
                debugPublication.textureWidth,
                debugPublication.textureHeight
            )
        }
#endif
        if let next = completion.next { schedule(next) }
    }

    private static func signature(
        for layer: SceneRenderDescriptor.Layer,
        snapshot: SceneDynamicSnapshot?
    ) -> SceneDynamicTextSignature {
        let authoredStyle = layer.textStyle!
        let content = stringValue(
            snapshot?[.text(layerID: layer.id, field: .content)]?.value
        ) ?? layer.text!
        let pointSize = scalarValue(
            snapshot?[.text(layerID: layer.id, field: .pointSize)]?.value
        ).map { Float(max(1, min($0, 1_024))) } ?? authoredStyle.pointSize
        let color = colorValue(
            snapshot?[.text(layerID: layer.id, field: .color)]?.value
        ) ?? authoredStyle.colorRGB
        let maxWidth = authoredStyle.limitWidth
            ? scalarValue(snapshot?[.text(layerID: layer.id, field: .maxWidth)]?.value)
                .map { Float(max(1, min($0, 16_384))) } ?? authoredStyle.maxWidth
            : authoredStyle.maxWidth
        return .init(
            content: content,
            pointSize: pointSize,
            colorRGB: color,
            maxWidth: maxWidth
        )
    }

    private static func stringValue(_ value: SceneDynamicValue?) -> String? {
        guard case let .string(string) = value else { return nil }
        return string
    }

    private static func scalarValue(_ value: SceneDynamicValue?) -> Double? {
        guard case let .scalar(number) = value else { return nil }
        return number
    }

    private static func colorValue(_ value: SceneDynamicValue?) -> [Float]? {
        guard case let .vector3(red, green, blue) = value else { return nil }
        return [red, green, blue].map { Float(max(0, min($0, 1))) }
    }
}
