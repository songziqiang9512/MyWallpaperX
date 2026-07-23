import Foundation
import Metal

final class SceneDynamicTextTextureStore: @unchecked Sendable {
    private let cacheDirectory: URL
    private let device: MTLDevice
    private let layersByID: [Int: SceneRenderDescriptor.Layer]
    private let queue = DispatchQueue(label: "com.mywallpaperx.scene.dynamic-text", qos: .userInitiated)
    private let lock = NSLock()
    private var generationState = SceneDynamicTextGenerationState()
    private var currentTextures: [Int: MTLTexture]

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
            let generation = generationState.request(layerID: layer.id, signature: signature)
            lock.unlock()
            guard let generation else { continue }
            queue.async { [weak self] in
                self?.render(layerID: layer.id, signature: signature, generation: generation)
            }
        }
    }

    func textures() -> [Int: MTLTexture] {
        lock.lock()
        defer { lock.unlock() }
        return currentTextures
    }

    deinit {
        lock.lock()
        generationState.reset()
        lock.unlock()
    }

    private func render(
        layerID: Int,
        signature: SceneDynamicTextSignature,
        generation: UInt64
    ) {
        guard let layer = layersByID[layerID] else { return }
        let texture = SceneTextTextureLoader.makeTexture(
            for: layer,
            content: signature.content,
            pointSize: signature.pointSize,
            colorRGB: signature.colorRGB,
            cacheDirectory: cacheDirectory,
            device: device
        )
        lock.lock()
        defer { lock.unlock() }
        guard generationState.complete(
            layerID: layerID,
            generation: generation,
            succeeded: texture != nil
        ), let texture else { return }
        currentTextures[layerID] = texture
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
        return .init(content: content, pointSize: pointSize, colorRGB: color)
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
