import Foundation
import Metal

final class SceneDynamicTextTextureStore: @unchecked Sendable {
    struct Snapshot {
        let textures: [Int: MTLTexture]
        let renderSizes: [Int: [Float]]
        let publications: [Int: SceneTextureProviderPublication]
    }

    private let cacheDirectory: URL
    private let device: MTLDevice
    private let layersByID: [Int: SceneRenderDescriptor.Layer]
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

    func update(from snapshot: SceneDynamicSnapshot) {
        for layer in layersByID.values {
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
        let publications = Dictionary(uniqueKeysWithValues: currentTextures.compactMap {
            layerID, texture in
            generationState.readyGeneration(layerID: layerID).map {
                (
                    layerID,
                    SceneTextureProviderPublication(
                        texture: texture,
                        contentGeneration: $0
                    )
                )
            }
        })
        return Snapshot(
            textures: currentTextures,
            renderSizes: currentRenderSizes,
            publications: publications
        )
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
        guard let layer = layersByID[request.layerID] else { return }
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
        var debugPublication: (layerID: Int, generation: UInt64, maxWidth: Float)?
#endif
        lock.lock()
        let completion = generationState.finish(request, succeeded: rendered != nil)
        if completion.accepted, let rendered {
            currentTextures[request.layerID] = rendered.texture
            currentRenderSizes[request.layerID] = rendered.renderSizeWH
#if DEBUG
            if debugLoggedDynamicLayers.insert(request.layerID).inserted {
                debugPublication = (
                    request.layerID, request.generation, request.signature.maxWidth
                )
            }
#endif
        }
        lock.unlock()
#if DEBUG
        if let debugPublication {
            NSLog(
                "MWX DEBUG SCENE: phase=dynamic-text-published layer=%d generation=%llu maxWidth=%.3f",
                debugPublication.layerID,
                debugPublication.generation,
                debugPublication.maxWidth
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
