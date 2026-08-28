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
}

/// One launch owns one repository. Immutable Metal states are shared by every
/// surface and are compiled only when an executing effect first asks for them.
final class SceneImageEffectPipelineRepository {
    let device: MTLDevice

    private let standardBlurSlot: ScenePipelineSlot<SceneStandardBlurPipeline>
    private let spotLightSlot: ScenePipelineSlot<SceneSpotLightPipeline>
    private let pulseSlot: ScenePipelineSlot<ScenePulsePipeline>

    init(device: MTLDevice) {
        self.device = device
        standardBlurSlot = .init { SceneStandardBlurPipeline(device: device) }
        spotLightSlot = .init { SceneSpotLightPipeline(device: device) }
        pulseSlot = .init { ScenePulsePipeline(device: device) }
    }

    func standardBlur() -> SceneStandardBlurPipeline? { standardBlurSlot.resolve() }
    func spotLight() -> SceneSpotLightPipeline? { spotLightSlot.resolve() }
    func pulse() -> ScenePulsePipeline? { pulseSlot.resolve() }
}
