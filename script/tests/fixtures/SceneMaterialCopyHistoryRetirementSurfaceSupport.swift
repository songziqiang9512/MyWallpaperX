// External camera, Puppet, media and particle dependencies only. The actual
// Surface.updateSimulation method is compiled separately and owns adoption.
import CoreGraphics
import Foundation
import simd

struct SceneFrameTiming {
    let frameIndex: UInt64
    var simulationFrameTime: Double { 1 / 60 }
}
struct SceneFrameContext { let dynamicValues: SceneDynamicSnapshot }
struct SceneScriptMaterialFunctionMutation {}
struct SceneScriptPuppetBoneMutation {}
struct SceneScriptSurfaceInput {}
struct SceneAudioSpectrumSnapshot { static let silent = Self() }
struct ScenePuppetAnimationPlaybackRuntime { typealias FrameSnapshot = [Int: Int] }
struct SceneMediaThumbnailTextureStore { struct Snapshot {} }
struct SceneScriptLayerTopologySnapshot {
    let topologyRevision: UInt64
    let destroyedAuthoredLayerIDs: Set<Int>
}
struct ScenePuppetAttachmentFrameSnapshot { let framesByParentLayerID: [Int: Int] }
struct HistorySurfaceCameraProperties { var parallaxDelay: Double? { nil } }
extension SceneDynamicSnapshot {
    func cameraPropertyProjection() -> HistorySurfaceCameraProperties { .init() }
}
extension SceneRenderDescriptor {
    var camera: HistorySurfaceCameraProperties { .init() }
}
struct HistorySurfaceProjection {
    let descriptor: SceneRenderDescriptor
    let layersByID: [Int: SceneRenderDescriptor.Layer]
    let worldFrames: [Int: simd_float4x4]
}
struct HistorySurfaceCamera {}
final class HistorySurfaceRuntime {
    let submissions: SceneResolvedMaterialSubmissionCoordinator
    init(_ submissions: SceneResolvedMaterialSubmissionCoordinator) { self.submissions = submissions }
}
struct HistorySurfaceCompositor { let resolvedMaterialRuntime: HistorySurfaceRuntime? }
final class HistorySurfaceRenderer {
    let renderDescriptor: SceneRenderDescriptor
    let imageCompositor: HistorySurfaceCompositor
    init(_ owner: SceneResolvedMaterialSubmissionCoordinator, descriptor: SceneRenderDescriptor) {
        renderDescriptor = descriptor
        imageCompositor = .init(resolvedMaterialRuntime: .init(owner))
    }
    func resolveFrameWorldProjection(
        layerTopology: SceneScriptLayerTopologySnapshot?, dynamicValues: SceneDynamicSnapshot,
        puppetAttachmentFrames: ScenePuppetAttachmentFrameSnapshot
    ) -> HistorySurfaceProjection {
        .init(descriptor: renderDescriptor,
            layersByID: Dictionary(uniqueKeysWithValues: renderDescriptor.layers.map { ($0.id, $0) }),
            worldFrames: [:])
    }
    func makeCameraFrame(
        frameContext: SceneFrameContext, descriptor: SceneRenderDescriptor,
        layersByID: [Int: SceneRenderDescriptor.Layer], worldFrames: [Int: simd_float4x4]
    ) -> HistorySurfaceCamera { .init() }
}
final class HistorySurfacePuppet {
    var renderFrame: Int { fatalError("Puppet is outside the history fixture") }
    func apply(scriptBoneMutations: [SceneScriptPuppetBoneMutation]) {
        fatalError("Puppet is outside the history fixture")
    }
    func prepareFrame(animationFrame: Int) -> Int {
        fatalError("Puppet is outside the history fixture")
    }
}
struct HistorySurfacePointer { var current = SIMD2<Float>.zero; var previous = SIMD2<Float>.zero }
struct HistorySurfaceSmoother {
    func advance(delta: Double, delay: Double?) -> SIMD2<Float> { .zero }
}
final class HistorySurfaceParticles {
    func retire(layerIDs: Set<Int>) { fatalError("particles are outside the history fixture") }
}
final class SceneMetalView {
    struct SimulationFrame {
        let timing: SceneFrameTiming
        let context: SceneFrameContext
        let camera: HistorySurfaceCamera
        let projection: HistorySurfaceProjection
        let particles: [Int]
        let topology: SceneScriptLayerTopologySnapshot
        let mediaThumbnail: SceneMediaThumbnailTextureStore.Snapshot
        let mediaInputGeneration: UInt64
        let spriteTimes: [Int: Float]
        let puppetAnimationFrame: ScenePuppetAnimationPlaybackRuntime.FrameSnapshot
        let puppetRenderFrames: [Int: Int]
        let attachmentFrames: ScenePuppetAttachmentFrameSnapshot
    }
    let renderer: HistorySurfaceRenderer
    let spriteAnimationLayerIDs: Set<Int> = []
    let particlePipeline: HistorySurfaceParticles? = nil
    let requiresSceneScriptCameraWorldFrames = false
    let parallaxPointerSmoother = HistorySurfaceSmoother()
    var pointerState = HistorySurfacePointer()
    init(_ owner: SceneResolvedMaterialSubmissionCoordinator, descriptor: SceneRenderDescriptor) {
        renderer = .init(owner, descriptor: descriptor)
    }
    func retireSpriteAnimations(layerIDs: Set<Int>) {}
    func makeFrameContext(
        timing: SceneFrameTiming, dynamicValues: SceneDynamicSnapshot,
        materialFunctionMutations: [SceneScriptMaterialFunctionMutation],
        parallax: SIMD2<Float>, audioSpectrum: SceneAudioSpectrumSnapshot
    ) -> SceneFrameContext { .init(dynamicValues: dynamicValues) }
    func sceneScriptSurfaceInput(
        timing: SceneFrameTiming, dynamicValues: SceneDynamicSnapshot,
        descriptor: SceneRenderDescriptor, layersByID: [Int: SceneRenderDescriptor.Layer],
        worldFrames: [Int: simd_float4x4]
    ) -> SceneScriptSurfaceInput { .init() }
}
enum SceneDesktopWallpaperSession {
    final class Surface {
        let metalView: SceneMetalView
        let puppetPlaybackStates: [Int: HistorySurfacePuppet] = [:]
        var simulationFrame: SceneMetalView.SimulationFrame?
        init(_ owner: SceneResolvedMaterialSubmissionCoordinator, descriptor: SceneRenderDescriptor) {
            metalView = .init(owner, descriptor: descriptor)
        }
        func advanceParticles(
            timing: SceneFrameTiming, dynamicValues: SceneDynamicSnapshot,
            frameContext: SceneFrameContext, cameraFrame: HistorySurfaceCamera,
            frameProjection: HistorySurfaceProjection, performanceTelemetry: SceneFramePerformanceTelemetry?
        ) -> [Int] { [] }
    }
}
