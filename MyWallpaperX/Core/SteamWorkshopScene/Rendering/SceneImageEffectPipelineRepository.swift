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
    private let opacitySlot: ScenePipelineSlot<SceneOpacityPipeline>
    private let colorKeySlot: ScenePipelineSlot<SceneColorKeyPipeline>
    private let colorGradingSlot: ScenePipelineSlot<SceneColorGradingPipeline>
    private let shiftHueSlot: ScenePipelineSlot<SceneWorkshopShiftHuePipeline>
    private let audioBarsSlot: ScenePipelineSlot<SceneWorkshopAudioBarsPipeline>
    private let simpleAudioBarsSlot: ScenePipelineSlot<SceneWorkshopSimpleAudioBarsPipeline>
    private let workshopGradientSlot: ScenePipelineSlot<SceneWorkshopGradientPipeline>
    private let workshopShadowSlot: ScenePipelineSlot<SceneWorkshopShadowPipeline>
    private let spinSlot: ScenePipelineSlot<SceneSpinPipeline>
    private let proceduralNoiseSlot: ScenePipelineSlot<SceneProceduralNoisePipeline>
    private let filmGrainSlot: ScenePipelineSlot<SceneFilmGrainPipeline>
    private let lightShaftsSlot: ScenePipelineSlot<SceneLightShaftsPipeline>
    private let spotLightSlot: ScenePipelineSlot<SceneSpotLightPipeline>
    private let shakeSlot: ScenePipelineSlot<SceneShakePipeline>
    private let waterFlowSlot: ScenePipelineSlot<SceneWaterFlowPipeline>
    private let waterWavesSlot: ScenePipelineSlot<SceneWaterWavesPipeline>
    private let cursorRippleSlot: ScenePipelineSlot<SceneCursorRipplePipeline>
    private let foliageSwaySlot: ScenePipelineSlot<SceneFoliageSwayPipeline>
    private let waterRippleSlot: ScenePipelineSlot<SceneWaterRipplePipeline>
    private let depthParallaxSlot: ScenePipelineSlot<SceneDepthParallaxPipeline>
    private let xRaySlot: ScenePipelineSlot<SceneXRayPipeline>
    private let blendSlot: ScenePipelineSlot<SceneBlendPipeline>
    private let mediaThumbnailTransitionSlot:
        ScenePipelineSlot<SceneMediaThumbnailTransitionPipeline>
    private let tintSlot: ScenePipelineSlot<SceneTintPipeline>
    private let fisheyeZeroDistortionSlot:
        ScenePipelineSlot<SceneFisheyeZeroDistortionPipeline>
    private let pulseSlot: ScenePipelineSlot<ScenePulsePipeline>
    private let godraysSlot: ScenePipelineSlot<SceneGodraysPipeline>
    private let shineSlot: ScenePipelineSlot<SceneShinePipeline>
    private let authoredShaderSlot: ScenePipelineSlot<SceneAuthoredShaderPipelineCache>
    private let bloomSlot: ScenePipelineSlot<SceneBloomPipeline>
    private let gradientColorSlot: ScenePipelineSlot<SceneGradientColorPipeline>
    private let perspectiveOpacitySlot: ScenePipelineSlot<ScenePerspectiveOpacityPipeline>

    init(device: MTLDevice) {
        self.device = device
        gaussianBlurSlot = .init { SceneGaussianBlurPipeline(device: device) }
        standardBlurSlot = .init { SceneStandardBlurPipeline(device: device) }
        localContrastSlot = .init { SceneLocalContrastPipeline(device: device) }
        opacitySlot = .init { SceneOpacityPipeline(device: device) }
        colorKeySlot = .init { SceneColorKeyPipeline(device: device) }
        colorGradingSlot = .init { SceneColorGradingPipeline(device: device) }
        shiftHueSlot = .init { SceneWorkshopShiftHuePipeline(device: device) }
        audioBarsSlot = .init { SceneWorkshopAudioBarsPipeline(device: device) }
        simpleAudioBarsSlot = .init { SceneWorkshopSimpleAudioBarsPipeline(device: device) }
        workshopGradientSlot = .init { SceneWorkshopGradientPipeline(device: device) }
        workshopShadowSlot = .init { SceneWorkshopShadowPipeline(device: device) }
        spinSlot = .init { SceneSpinPipeline(device: device) }
        proceduralNoiseSlot = .init { SceneProceduralNoisePipeline(device: device) }
        filmGrainSlot = .init { SceneFilmGrainPipeline(device: device) }
        lightShaftsSlot = .init { SceneLightShaftsPipeline(device: device) }
        spotLightSlot = .init { SceneSpotLightPipeline(device: device) }
        shakeSlot = .init { SceneShakePipeline(device: device) }
        waterFlowSlot = .init { SceneWaterFlowPipeline(device: device) }
        waterWavesSlot = .init { SceneWaterWavesPipeline(device: device) }
        cursorRippleSlot = .init { SceneCursorRipplePipeline(device: device) }
        foliageSwaySlot = .init { SceneFoliageSwayPipeline(device: device) }
        waterRippleSlot = .init { SceneWaterRipplePipeline(device: device) }
        depthParallaxSlot = .init { SceneDepthParallaxPipeline(device: device) }
        xRaySlot = .init { SceneXRayPipeline(device: device) }
        blendSlot = .init { SceneBlendPipeline(device: device) }
        mediaThumbnailTransitionSlot = .init {
            SceneMediaThumbnailTransitionPipeline(device: device)
        }
        tintSlot = .init { SceneTintPipeline(device: device) }
        fisheyeZeroDistortionSlot = .init {
            SceneFisheyeZeroDistortionPipeline(device: device)
        }
        pulseSlot = .init { ScenePulsePipeline(device: device) }
        godraysSlot = .init { SceneGodraysPipeline(device: device) }
        shineSlot = .init { SceneShinePipeline(device: device) }
        authoredShaderSlot = .init { SceneAuthoredShaderPipelineCache(device: device) }
        bloomSlot = .init { SceneBloomPipeline(device: device) }
        gradientColorSlot = .init { SceneGradientColorPipeline(device: device) }
        perspectiveOpacitySlot = .init { ScenePerspectiveOpacityPipeline(device: device) }
    }

    func gaussianBlur() -> SceneGaussianBlurPipeline? { gaussianBlurSlot.resolve() }
    func standardBlur() -> SceneStandardBlurPipeline? { standardBlurSlot.resolve() }
    func localContrast() -> SceneLocalContrastPipeline? { localContrastSlot.resolve() }
    func opacity() -> SceneOpacityPipeline? { opacitySlot.resolve() }
    func colorKey() -> SceneColorKeyPipeline? { colorKeySlot.resolve() }
    func colorGrading() -> SceneColorGradingPipeline? { colorGradingSlot.resolve() }
    func shiftHue() -> SceneWorkshopShiftHuePipeline? { shiftHueSlot.resolve() }
    func audioBars() -> SceneWorkshopAudioBarsPipeline? { audioBarsSlot.resolve() }
    func simpleAudioBars() -> SceneWorkshopSimpleAudioBarsPipeline? {
        simpleAudioBarsSlot.resolve()
    }
    func workshopGradient() -> SceneWorkshopGradientPipeline? {
        workshopGradientSlot.resolve()
    }
    func workshopShadow() -> SceneWorkshopShadowPipeline? { workshopShadowSlot.resolve() }
    func spin() -> SceneSpinPipeline? { spinSlot.resolve() }
    func proceduralNoise() -> SceneProceduralNoisePipeline? {
        proceduralNoiseSlot.resolve()
    }
    func filmGrain() -> SceneFilmGrainPipeline? { filmGrainSlot.resolve() }
    func lightShafts() -> SceneLightShaftsPipeline? { lightShaftsSlot.resolve() }
    func spotLight() -> SceneSpotLightPipeline? { spotLightSlot.resolve() }
    func shake() -> SceneShakePipeline? { shakeSlot.resolve() }
    func waterFlow() -> SceneWaterFlowPipeline? { waterFlowSlot.resolve() }
    func waterWaves() -> SceneWaterWavesPipeline? { waterWavesSlot.resolve() }
    func cursorRipple() -> SceneCursorRipplePipeline? { cursorRippleSlot.resolve() }
    func foliageSway() -> SceneFoliageSwayPipeline? { foliageSwaySlot.resolve() }
    func waterRipple() -> SceneWaterRipplePipeline? { waterRippleSlot.resolve() }
    func depthParallax() -> SceneDepthParallaxPipeline? {
        depthParallaxSlot.resolve()
    }
    func xRay() -> SceneXRayPipeline? { xRaySlot.resolve() }
    func blend() -> SceneBlendPipeline? { blendSlot.resolve() }
    func mediaThumbnailTransition() -> SceneMediaThumbnailTransitionPipeline? {
        mediaThumbnailTransitionSlot.resolve()
    }
    func tint() -> SceneTintPipeline? { tintSlot.resolve() }
    func fisheyeZeroDistortion() -> SceneFisheyeZeroDistortionPipeline? {
        fisheyeZeroDistortionSlot.resolve()
    }
    func pulse() -> ScenePulsePipeline? { pulseSlot.resolve() }
    func godrays() -> SceneGodraysPipeline? { godraysSlot.resolve() }
    func shine() -> SceneShinePipeline? { shineSlot.resolve() }
    func authoredShader() -> SceneAuthoredShaderPipelineCache? {
        authoredShaderSlot.resolve()
    }
    func bloom() -> SceneBloomPipeline? { bloomSlot.resolve() }
    func gradientColor() -> SceneGradientColorPipeline? { gradientColorSlot.resolve() }
    func perspectiveOpacity() -> ScenePerspectiveOpacityPipeline? {
        perspectiveOpacitySlot.resolve()
    }
}
