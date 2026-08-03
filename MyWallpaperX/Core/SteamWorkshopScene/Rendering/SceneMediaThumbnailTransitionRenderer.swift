import Foundation
import CoreGraphics
import Metal

final class SceneMediaThumbnailTransitionRenderer {
    private struct PlaybackState {
        var observedGeneration: UInt64?
        var startedAt: Double?
        var midpointReported = false
        var completionReported = false
        var publicationGeneration: UInt64 = 0
    }

    private struct Output {
        let texture: MTLTexture
        let width: Int
        let height: Int
    }

    private let device: MTLDevice
    private let pipeline: SceneMediaThumbnailTransitionPipeline
    private var states: [Int: PlaybackState] = [:]
    private var outputs: [Int: Output] = [:]

    init(
        device: MTLDevice,
        pipeline: SceneMediaThumbnailTransitionPipeline
    ) {
        self.device = device
        self.pipeline = pipeline
    }

    func encode(
        program: SceneMediaThumbnailBindingProgram,
        resources: [Int: SceneMediaThumbnailTransitionTexture],
        media: SceneMediaThumbnailTextureStore.Snapshot,
        sceneTime: Double,
        commandBuffer: MTLCommandBuffer
    ) -> [Int: SceneTextureProviderPublication] {
        guard media.generation > 0,
              sceneTime.isFinite,
              let current = media.current,
              let previous = media.publications[
                  SceneMediaThumbnailBindingProgram.previousIdentity
              ] else {
            observeUnavailableGeneration(
                media.generation,
                plans: program.previousTransitionsByLayerID
            )
            return [:]
        }

        var publications: [Int: SceneTextureProviderPublication] = [:]
        for (layerID, plan) in program.previousTransitionsByLayerID.sorted(
            by: { $0.key < $1.key }
        ) {
            guard let gradient = resources[layerID]?.arguments(for: plan) else {
                continue
            }
            var state = states[layerID] ?? PlaybackState()
            if state.observedGeneration == nil {
                state.observedGeneration = media.generation
                states[layerID] = state
                continue
            }
            if state.observedGeneration != media.generation {
                state.observedGeneration = media.generation
                state.startedAt = sceneTime
                state.midpointReported = false
                state.completionReported = false
#if DEBUG
                print(
                    "MWX media thumbnail transition: layer=\(layerID)"
                        + " generation=\(media.generation) phase=started"
                        + " duration=\(plan.durationSeconds)"
                )
#endif
            }
            guard let startedAt = state.startedAt else {
                states[layerID] = state
                continue
            }
            let progress = min(max((sceneTime - startedAt) / plan.durationSeconds, 0), 1)
            if progress >= 1 {
                if !state.completionReported {
                    state.completionReported = true
#if DEBUG
                    print(
                        "MWX media thumbnail transition: layer=\(layerID)"
                            + " generation=\(media.generation) phase=completed"
                    )
#endif
                }
                state.startedAt = nil
                states[layerID] = state
                continue
            }
            if progress >= 0.5 && !state.midpointReported {
                state.midpointReported = true
#if DEBUG
                print(
                    "MWX media thumbnail transition: layer=\(layerID)"
                        + " generation=\(media.generation) phase=midpoint"
                )
#endif
            }
            guard let target = outputTexture(
                layerID: layerID,
                width: current.texture.width,
                height: current.texture.height
            ), pipeline.encode(
                current: current.texture,
                previous: previous.texture,
                gradient: gradient,
                target: target,
                amount: Float(1 - progress),
                gradientScale: plan.gradientScale,
                commandBuffer: commandBuffer
            ) else {
                states[layerID] = state
                continue
            }
            state.publicationGeneration &+= 1
            let size = CGSize(width: target.width, height: target.height)
            publications[layerID] = SceneTextureProviderPublication(
                requestIdentity: .layerSource(layerID),
                candidate: SceneTextureCandidate(
                    texture: target,
                    identity: .provider(
                        .mediaThumbnailTransition(layerID: layerID)
                    ),
                    generation: .provider(
                        contentGeneration: state.publicationGeneration
                    ),
                    purpose: .premultipliedColor,
                    content: .color(.resolved(.premultipliedAlpha)),
                    physicalSize: size,
                    mappedSize: size,
                    uvTransform: .identity,
                    sampling: .linearClamp
                ),
                contentGeneration: state.publicationGeneration
            )
            states[layerID] = state
        }
        return publications
    }

    private func observeUnavailableGeneration(
        _ generation: UInt64,
        plans: [Int: SceneMediaThumbnailTransitionPlan]
    ) {
        guard generation > 0 else { return }
        for layerID in plans.keys {
            var state = states[layerID] ?? PlaybackState()
            if state.observedGeneration != generation {
                state.observedGeneration = generation
                state.startedAt = nil
                state.midpointReported = false
                state.completionReported = false
            }
            states[layerID] = state
        }
    }

    private func outputTexture(
        layerID: Int,
        width: Int,
        height: Int
    ) -> MTLTexture? {
        guard width > 0, height > 0, width <= 256, height <= 256 else {
            return nil
        }
        if let output = outputs[layerID],
           output.width == width,
           output.height == height {
            return output.texture
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            return nil
        }
        texture.label = "Scene media thumbnail transition layer \(layerID)"
        outputs[layerID] = Output(texture: texture, width: width, height: height)
        return texture
    }
}
