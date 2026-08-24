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

    private let gaussianBlurSlot: ScenePipelineSlot<SceneGaussianBlurPipeline>
    private let standardBlurSlot: ScenePipelineSlot<SceneStandardBlurPipeline>
    private let proceduralNoiseSlot: ScenePipelineSlot<SceneProceduralNoisePipeline>
    private let spotLightSlot: ScenePipelineSlot<SceneSpotLightPipeline>
    private let waterWavesSlot: ScenePipelineSlot<SceneWaterWavesPipeline>
    private let waterCausticsSlot: ScenePipelineSlot<SceneWaterCausticsPipeline>
    private let xRaySlot: ScenePipelineSlot<SceneXRayPipeline>
    private let blendSlot: ScenePipelineSlot<SceneBlendPipeline>
    private let pulseSlot: ScenePipelineSlot<ScenePulsePipeline>
    private let godraysSlot: ScenePipelineSlot<SceneGodraysPipeline>

    init(device: MTLDevice) {
        self.device = device
        gaussianBlurSlot = .init { SceneGaussianBlurPipeline(device: device) }
        standardBlurSlot = .init { SceneStandardBlurPipeline(device: device) }
        proceduralNoiseSlot = .init { SceneProceduralNoisePipeline(device: device) }
        spotLightSlot = .init { SceneSpotLightPipeline(device: device) }
        waterWavesSlot = .init { SceneWaterWavesPipeline(device: device) }
        waterCausticsSlot = .init { SceneWaterCausticsPipeline(device: device) }
        xRaySlot = .init { SceneXRayPipeline(device: device) }
        blendSlot = .init { SceneBlendPipeline(device: device) }
        pulseSlot = .init { ScenePulsePipeline(device: device) }
        godraysSlot = .init { SceneGodraysPipeline(device: device) }
    }

    func gaussianBlur() -> SceneGaussianBlurPipeline? { gaussianBlurSlot.resolve() }
    func standardBlur() -> SceneStandardBlurPipeline? { standardBlurSlot.resolve() }
    func proceduralNoise() -> SceneProceduralNoisePipeline? {
        proceduralNoiseSlot.resolve()
    }
    func spotLight() -> SceneSpotLightPipeline? { spotLightSlot.resolve() }
    func waterWaves() -> SceneWaterWavesPipeline? { waterWavesSlot.resolve() }
    func waterCaustics() -> SceneWaterCausticsPipeline? { waterCausticsSlot.resolve() }
    func xRay() -> SceneXRayPipeline? { xRaySlot.resolve() }
    func blend() -> SceneBlendPipeline? { blendSlot.resolve() }
    func pulse() -> ScenePulsePipeline? { pulseSlot.resolve() }
    func godrays() -> SceneGodraysPipeline? { godraysSlot.resolve() }
}
