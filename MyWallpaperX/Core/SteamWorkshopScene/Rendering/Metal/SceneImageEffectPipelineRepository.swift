import Foundation
import Metal

final class ScenePipelineSlot<Value>: @unchecked Sendable {
    private enum State {
        case unresolved
        case resolved(Value?)
    }

    private let lock = NSLock()
    private let factory: () -> Value?
    private var state = State.unresolved

    init(factory: @escaping () -> Value?) {
        self.factory = factory
    }

    func resolve() -> Value? {
        lock.lock()
        defer { lock.unlock() }
        switch state {
        case .resolved(let value):
            return value
        case .unresolved:
            let value = factory()
            state = .resolved(value)
            return value
        }
    }

    /// Reads an already-resolved value without invoking the factory. Resource
    /// telemetry must never compile a lazy pipeline merely to sample a gauge.
    func resolvedValue() -> Value? {
        lock.lock()
        defer { lock.unlock() }
        guard case let .resolved(value) = state else { return nil }
        return value
    }
}

/// One launch owns one repository. Immutable Metal states are shared by every
/// surface. Required direct-draw state is prepared before activation; optional
/// effect states are resolved on demand.
final class SceneImageEffectPipelineRepository {
    let device: MTLDevice

    private let layerColorBlendStateSlot:
        ScenePipelineSlot<SceneLayerColorBlendPipelineState>
    private let spotLightSlot: ScenePipelineSlot<SceneSpotLightPipeline>
    private let directDrawSlot: ScenePipelineSlot<SceneImageLayerPipeline>

    init(device: MTLDevice, pixelFormat: MTLPixelFormat = .bgra8Unorm) {
        self.device = device
        layerColorBlendStateSlot = .init {
            SceneLayerColorBlendPipelineState(device: device, pixelFormat: pixelFormat)
        }
        spotLightSlot = .init { SceneSpotLightPipeline(device: device, pixelFormat: pixelFormat) }
        directDrawSlot = .init {
            SceneImageLayerPipeline(device: device, pixelFormat: pixelFormat, blendMode: .alphaWeightedAdditive)
        }
    }

    func layerColorBlendState() -> SceneLayerColorBlendPipelineState? {
        layerColorBlendStateSlot.resolve()
    }

    func spotLight() -> SceneSpotLightPipeline? { spotLightSlot.resolve() }

    /// Independent quad assets emit light over the existing composition.
    /// Resolve at launch; ordinary frames may only read the prepared state.
    func prepareDirectDraw() -> Bool { directDrawSlot.resolve() != nil }
    var directDraw: SceneImageLayerPipeline? { directDrawSlot.resolvedValue() }
}
