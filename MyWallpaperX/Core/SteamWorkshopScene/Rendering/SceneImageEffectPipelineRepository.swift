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
    private let localContrastSlot: ScenePipelineSlot<SceneLocalContrastPipeline>
    private let colorGradingSlot: ScenePipelineSlot<SceneColorGradingPipeline>
    private let proceduralNoiseSlot: ScenePipelineSlot<SceneProceduralNoisePipeline>
    private let spotLightSlot: ScenePipelineSlot<SceneSpotLightPipeline>
    private let shakeSlot: ScenePipelineSlot<SceneShakePipeline>
    private let waterFlowSlot: ScenePipelineSlot<SceneWaterFlowPipeline>
    private let waterWavesSlot: ScenePipelineSlot<SceneWaterWavesPipeline>
    private let waterCausticsSlot: ScenePipelineSlot<SceneWaterCausticsPipeline>
    private let cursorRippleSlot: ScenePipelineSlot<SceneCursorRipplePipeline>
    private let waterRippleSlot: ScenePipelineSlot<SceneWaterRipplePipeline>
    private let depthParallaxSlot: ScenePipelineSlot<SceneDepthParallaxPipeline>
    private let xRaySlot: ScenePipelineSlot<SceneXRayPipeline>
    private let blendSlot: ScenePipelineSlot<SceneBlendPipeline>
    private let pulseSlot: ScenePipelineSlot<ScenePulsePipeline>
    private let godraysSlot: ScenePipelineSlot<SceneGodraysPipeline>
    private let shineSlot: ScenePipelineSlot<SceneShinePipeline>

    init(device: MTLDevice) {
        self.device = device
        gaussianBlurSlot = .init { SceneGaussianBlurPipeline(device: device) }
        standardBlurSlot = .init { SceneStandardBlurPipeline(device: device) }
        localContrastSlot = .init { SceneLocalContrastPipeline(device: device) }
        colorGradingSlot = .init { SceneColorGradingPipeline(device: device) }
        proceduralNoiseSlot = .init { SceneProceduralNoisePipeline(device: device) }
        spotLightSlot = .init { SceneSpotLightPipeline(device: device) }
        shakeSlot = .init { SceneShakePipeline(device: device) }
        waterFlowSlot = .init { SceneWaterFlowPipeline(device: device) }
        waterWavesSlot = .init { SceneWaterWavesPipeline(device: device) }
        waterCausticsSlot = .init { SceneWaterCausticsPipeline(device: device) }
        cursorRippleSlot = .init { SceneCursorRipplePipeline(device: device) }
        waterRippleSlot = .init { SceneWaterRipplePipeline(device: device) }
        depthParallaxSlot = .init { SceneDepthParallaxPipeline(device: device) }
        xRaySlot = .init { SceneXRayPipeline(device: device) }
        blendSlot = .init { SceneBlendPipeline(device: device) }
        pulseSlot = .init { ScenePulsePipeline(device: device) }
        godraysSlot = .init { SceneGodraysPipeline(device: device) }
        shineSlot = .init { SceneShinePipeline(device: device) }
    }

    func gaussianBlur() -> SceneGaussianBlurPipeline? { gaussianBlurSlot.resolve() }
    func standardBlur() -> SceneStandardBlurPipeline? { standardBlurSlot.resolve() }
    func localContrast() -> SceneLocalContrastPipeline? { localContrastSlot.resolve() }
    func colorGrading() -> SceneColorGradingPipeline? { colorGradingSlot.resolve() }
    func proceduralNoise() -> SceneProceduralNoisePipeline? {
        proceduralNoiseSlot.resolve()
    }
    func spotLight() -> SceneSpotLightPipeline? { spotLightSlot.resolve() }
    func shake() -> SceneShakePipeline? { shakeSlot.resolve() }
    func waterFlow() -> SceneWaterFlowPipeline? { waterFlowSlot.resolve() }
    func waterWaves() -> SceneWaterWavesPipeline? { waterWavesSlot.resolve() }
    func waterCaustics() -> SceneWaterCausticsPipeline? { waterCausticsSlot.resolve() }
    func cursorRipple() -> SceneCursorRipplePipeline? { cursorRippleSlot.resolve() }
    func waterRipple() -> SceneWaterRipplePipeline? { waterRippleSlot.resolve() }
    func depthParallax() -> SceneDepthParallaxPipeline? {
        depthParallaxSlot.resolve()
    }
    func xRay() -> SceneXRayPipeline? { xRaySlot.resolve() }
    func blend() -> SceneBlendPipeline? { blendSlot.resolve() }
    func pulse() -> ScenePulsePipeline? { pulseSlot.resolve() }
    func godrays() -> SceneGodraysPipeline? { godraysSlot.resolve() }
    func shine() -> SceneShinePipeline? { shineSlot.resolve() }
}
