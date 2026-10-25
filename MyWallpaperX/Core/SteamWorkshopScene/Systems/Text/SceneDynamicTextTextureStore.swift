import CoreGraphics
import Foundation
import Metal

final class SceneDynamicTextTextureStore: @unchecked Sendable {
    struct Snapshot {
        let layerSources: [Int: SceneLayerSourcePublication]
    }

    private let resourceView: SceneResourceView?
    private let device: MTLDevice
    private let onPublication: (@Sendable (SceneDynamicTextTextureStore) -> Void)?
    private let authoredLayerIDs: Set<Int>
    private var dynamicTextFieldsByLayerID: [Int: Set<SceneDynamicTextField>]
    private var layersByID: [Int: SceneRenderDescriptor.Layer]
    private let queue = DispatchQueue(label: "com.mywallpaperx.scene.dynamic-text", qos: .userInitiated)
    private let lock = NSLock()
    private var closed = false
    private var generationState = SceneDynamicTextGenerationState()
    private var currentRasters: [Int: SceneTextTextureLoader.RasterizedTexture]
    private var cachedSnapshot: Snapshot?
    private var snapshotDirty = true
    private var preparedFrameSnapshot: Snapshot?
    private var submittedFrameSnapshot: Snapshot?
#if DEBUG
    private var debugLoggedDynamicLayers: Set<Int> = []
#endif

    init(
        descriptor: SceneRenderDescriptor,
        resourceView: SceneResourceView?,
        device: MTLDevice,
        initialRasters: [Int: SceneTextTextureLoader.RasterizedTexture],
        dynamicTextFieldsByLayerID: [Int: Set<SceneDynamicTextField>] = [:],
        onPublication: (@Sendable (SceneDynamicTextTextureStore) -> Void)? = nil
    ) {
        // Authored hidden text can be shown by a later script/property event.
        // Prepare its source once; frame visibility owns actual composition.
        let layers = descriptor.layers.filter {
            $0.contentKind == "text"
                && $0.text != nil
                && $0.textStyle != nil
        }
        self.resourceView = resourceView
        self.device = device
        self.onPublication = onPublication
        self.layersByID = Dictionary(uniqueKeysWithValues: layers.map { ($0.id, $0) })
        authoredLayerIDs = Set(layers.map(\.id))
        self.dynamicTextFieldsByLayerID = dynamicTextFieldsByLayerID
        self.currentRasters = initialRasters
        for layer in layers {
            generationState.registerInitial(
                layerID: layer.id,
                signature: Self.signature(
                    for: layer, snapshot: nil,
                    dynamicFields: dynamicTextFieldsByLayerID[layer.id] ?? []
                ),
                isReady: initialRasters[layer.id] != nil
            )
        }
    }

    func update(
        from snapshot: SceneDynamicSnapshot,
        dynamicLayers: [SceneRenderDescriptor.Layer] = [],
        dynamicTextFieldsByLayerID: [Int: Set<SceneDynamicTextField>] = [:]
    ) {
        // A static authored scene has no provider work to perform after the
        // initial texture publication. Keep the lock as the authoritative
        // lifecycle boundary, but avoid rebuilding admitted sets and layer
        // tuples on every successful frame. Dynamic field interest, an
        // admitted runtime layer, or a pending authored-to-static transition
        // all fall through to the normal update path below.
        let incomingHasDynamicTextFields = dynamicTextFieldsByLayerID.values
            .contains { !$0.isEmpty }
        if dynamicLayers.isEmpty && !incomingHasDynamicTextFields {
            lock.lock()
            guard !closed else { lock.unlock(); return }
            let hasAdmittedDynamicLayer = layersByID.keys.contains {
                !authoredLayerIDs.contains($0)
            }
            let hasAuthoredDynamicFields = authoredLayerIDs.contains {
                !(self.dynamicTextFieldsByLayerID[$0] ?? []).isEmpty
            }
            if !hasAdmittedDynamicLayer && !hasAuthoredDynamicFields {
                lock.unlock()
                return
            }
            lock.unlock()
        }

        let admittedDynamic = dynamicLayers.filter {
            $0.contentKind == "text" && $0.text != nil && $0.textStyle != nil
        }
        let admittedIDs = Set(admittedDynamic.map(\.id))
        lock.lock()
        guard !closed else { lock.unlock(); return }
        var signatureRefreshLayerIDs: Set<Int> = []
        for layerID in authoredLayerIDs {
            let nextFields = dynamicTextFieldsByLayerID[layerID] ?? []
            if self.dynamicTextFieldsByLayerID[layerID] != nextFields {
                signatureRefreshLayerIDs.insert(layerID)
                self.dynamicTextFieldsByLayerID[layerID] = nextFields
            }
        }
        let retired = Set(layersByID.keys).subtracting(authoredLayerIDs).subtracting(admittedIDs)
        for layerID in retired {
            layersByID.removeValue(forKey: layerID)
            currentRasters.removeValue(forKey: layerID)
            self.dynamicTextFieldsByLayerID.removeValue(forKey: layerID)
            snapshotDirty = true
            generationState.unregister(layerID: layerID)
        }
        for layer in admittedDynamic {
            if layersByID[layer.id] == nil {
                layersByID[layer.id] = layer
                self.dynamicTextFieldsByLayerID[layer.id] = Self.allTextFields
                let signature = Self.signature(
                    for: layer, snapshot: nil,
                    dynamicFields: Self.allTextFields
                )
                if let request = generationState.registerDynamic(
                    layerID: layer.id, signature: signature
                ) {
                    scheduleLocked(request)
                }
            } else {
                layersByID[layer.id] = layer
            }
        }
        let layers = layersByID.map { layerID, layer in
            (layer, dynamicTextFieldsByLayerID[layerID] ?? [])
        }
        lock.unlock()
        for (layer, dynamicFields) in layers {
            guard !dynamicFields.isEmpty
                || signatureRefreshLayerIDs.contains(layer.id) else { continue }
            let signature = Self.signature(
                for: layer, snapshot: snapshot, dynamicFields: dynamicFields
            )
            lock.lock()
            guard !closed else { lock.unlock(); return }
            let request = generationState.schedule(layerID: layer.id, signature: signature)
            if let request { scheduleLocked(request) }
            lock.unlock()
        }
    }

    /// Stops admission without waiting for synchronous font drawing to return.
    func close() {
        lock.lock()
        closeLocked()
        lock.unlock()
    }

    /// The tail runs after every admitted render has returned and released its
    /// temporary font/bitmap bytes. Admission and the tail share the same lock.
    func closeAndDrain(completion: @escaping @Sendable () -> Void) {
        lock.lock()
        closeLocked()
        queue.async { [self] in
            withExtendedLifetime(self) { completion() }
        }
        lock.unlock()
    }

    private func closeLocked() {
        guard !closed else { return }
        closed = true
        generationState.reset()
    }

    /// Pins the currently published provider view for one host frame. Async
    /// raster completion may replace `currentRasters` while another surface
    /// is encoding; the host outcome decides when that replacement becomes
    /// visible to the next frame.
    func prepareFrame() -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        if let preparedFrameSnapshot { return preparedFrameSnapshot }
        let snapshot = makeSnapshotLocked()
        preparedFrameSnapshot = snapshot
        return snapshot
    }

    func commitPreparedFrame() {
        lock.lock()
        submittedFrameSnapshot = preparedFrameSnapshot ?? submittedFrameSnapshot
        preparedFrameSnapshot = nil
        lock.unlock()
    }

    /// Cursor callbacks run before the next texture frame is prepared. Use
    /// the last submitted raster geometry, not a newer async-ready result.
    func submittedSnapshot() -> Snapshot? {
        lock.lock()
        defer { lock.unlock() }
        return submittedFrameSnapshot
    }

    func discardPreparedFrame() {
        lock.lock()
        preparedFrameSnapshot = nil
        lock.unlock()
    }

    func snapshot() -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        if let preparedFrameSnapshot { return preparedFrameSnapshot }
        return makeSnapshotLocked()
    }

    private func makeSnapshotLocked() -> Snapshot {
        if !snapshotDirty, let cachedSnapshot { return cachedSnapshot }
        let pairs: [(Int, SceneLayerSourcePublication)] = currentRasters.compactMap {
            layerID, raster in
            guard let generation = generationState.readyGeneration(layerID: layerID) else {
                return nil
            }
            let texture = raster.texture
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
                renderSizeWH: raster.renderSizeWH,
                textCenterOffsetY: raster.centerOffsetY
            ) else { return nil }
            return (layerID, layerSource)
        }
        let layerSources = Dictionary(uniqueKeysWithValues: pairs)
        let snapshot = Snapshot(layerSources: layerSources)
        cachedSnapshot = snapshot
        snapshotDirty = false
        return snapshot
    }

    deinit {
        lock.lock()
        generationState.reset()
        lock.unlock()
    }

    private func scheduleLocked(_ request: SceneDynamicTextGenerationState.RenderRequest) {
        queue.async { [weak self] in self?.render(request) }
    }

    private func render(_ request: SceneDynamicTextGenerationState.RenderRequest) {
        lock.lock()
        let layer = closed ? nil : layersByID[request.layerID]
        let preparedFont = currentRasters[request.layerID]?.sourceFont
        lock.unlock()
        guard let layer else { return }
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--mwx-debug-scene-evidence-dir"),
           let rawDelay = ProcessInfo.processInfo.environment["MWX_SCENE_DEBUG_TEXT_RASTER_DELAY"],
           let delay = Double(rawDelay), delay.isFinite, delay > 0, delay <= 5 {
            Thread.sleep(forTimeInterval: delay)
        }
#endif
        let rendered: SceneTextTextureLoader.RasterizedTexture?
        do {
            let candidate = try SceneTextTextureLoader.makeDynamicTexture(
                for: layer, content: request.signature.content,
                fontPath: request.signature.fontPath, pointSize: request.signature.pointSize,
                colorRGB: request.signature.colorRGB, maxWidth: request.signature.maxWidth,
                resourceView: resourceView, preparedFont: preparedFont, device: device,
                checkCancellation: { try self.checkRendering(request) })
            try checkRendering(request)
            rendered = candidate
        } catch {
            rendered = nil
#if DEBUG
            NSLog("MWX Scene text layer=%d raster rejected: %@", request.layerID, String(describing: error))
#endif
        }
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
            currentRasters[request.layerID] = rendered
            snapshotDirty = true
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
        if let next = completion.next { scheduleLocked(next) }
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
        if completion.accepted, rendered != nil { onPublication?(self) }
    }

    private func checkRendering(_ request: SceneDynamicTextGenerationState.RenderRequest) throws {
        lock.lock()
        let active = !closed && layersByID[request.layerID] != nil
            && generationState.isRendering(request)
        lock.unlock()
        guard active else { throw CancellationError() }
    }

    private static func signature(
        for layer: SceneRenderDescriptor.Layer,
        snapshot: SceneDynamicSnapshot?,
        dynamicFields: Set<SceneDynamicTextField>
    ) -> SceneDynamicTextSignature {
        let authoredStyle = layer.textStyle!
        let content = dynamicFields.contains(.content)
            ? stringValue(
                snapshot?[.text(layerID: layer.id, field: .content)]?.value
            ) ?? layer.text!
            : layer.text!
        let fontPath = dynamicFields.contains(.font)
            ? stringValue(
                snapshot?[.text(layerID: layer.id, field: .font)]?.value
            ).flatMap { $0.isEmpty ? nil : $0 } ?? authoredStyle.fontPath
            : authoredStyle.fontPath
        let pointSize = dynamicFields.contains(.pointSize)
            ? scalarValue(
                snapshot?[.text(layerID: layer.id, field: .pointSize)]?.value
            ).flatMap(SceneTextDescriptor.renderedPointSize) ?? authoredStyle.pointSize
            : authoredStyle.pointSize
        let color = dynamicFields.contains(.color)
            ? colorValue(
                snapshot?[.text(layerID: layer.id, field: .color)]?.value
            ) ?? authoredStyle.colorRGB
            : authoredStyle.colorRGB
        let maxWidth = authoredStyle.limitWidth
            ? dynamicFields.contains(.maxWidth)
                ? scalarValue(
                    snapshot?[.text(layerID: layer.id, field: .maxWidth)]?.value
                ).map { Float(max(1, min($0, 16_384))) } ?? authoredStyle.maxWidth
                : authoredStyle.maxWidth
            : authoredStyle.maxWidth
        return .init(
            content: content,
            fontPath: fontPath,
            pointSize: pointSize,
            colorRGB: color,
            maxWidth: maxWidth
        )
    }

    private static let allTextFields: Set<SceneDynamicTextField> = [
        .content, .font, .pointSize, .color, .maxWidth
    ]

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
