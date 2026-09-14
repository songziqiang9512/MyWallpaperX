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
/// surface and are compiled only when an executing effect first asks for them.
final class SceneImageEffectPipelineRepository {
    let device: MTLDevice

    private let layerColorBlendStateSlot:
        ScenePipelineSlot<SceneLayerColorBlendPipelineState>
    private let spotLightSlot: ScenePipelineSlot<SceneSpotLightPipeline>

    init(device: MTLDevice) {
        self.device = device
        layerColorBlendStateSlot = .init {
            SceneLayerColorBlendPipelineState(device: device)
        }
        spotLightSlot = .init { SceneSpotLightPipeline(device: device) }
    }

    func layerColorBlendState() -> SceneLayerColorBlendPipelineState? {
        layerColorBlendStateSlot.resolve()
    }

    func spotLight() -> SceneSpotLightPipeline? { spotLightSlot.resolve() }
}
