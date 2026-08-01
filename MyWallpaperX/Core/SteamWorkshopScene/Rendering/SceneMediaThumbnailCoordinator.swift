import Metal

/// Per-surface owner for decoded media providers and the event-local previous
/// cover transition. A newly created surface observes the current generation as
/// its baseline and only plays after a later provider generation arrives.
final class SceneMediaThumbnailCoordinator {
    let program: SceneMediaThumbnailBindingProgram

    private let textureStore: SceneMediaThumbnailTextureStore
    private let transitionRenderer: SceneMediaThumbnailTransitionRenderer?
    private var transitionTextures: [Int: SceneMediaThumbnailTransitionTexture] = [:]

    init(
        program: SceneMediaThumbnailBindingProgram,
        device: MTLDevice,
        pipelineRepository: SceneImageEffectPipelineRepository
    ) {
        self.program = program
        textureStore = SceneMediaThumbnailTextureStore(device: device)
        transitionRenderer = program.previousTransitionsByLayerID.isEmpty ? nil
            : pipelineRepository.mediaThumbnailTransition().map {
                SceneMediaThumbnailTransitionRenderer(device: device, pipeline: $0)
            }
    }

    func loadTransitionTextures(
        resolver: SceneTexturePathResolver,
        loader: SceneTextureLoader,
        device: MTLDevice
    ) -> [String] {
        let load = SceneMediaThumbnailTransitionTextureLoader.load(
            program: program,
            resolver: resolver,
            loader: loader,
            device: device
        )
        transitionTextures = load.textures
        return load.reportLines
    }

    func update() -> SceneMediaThumbnailTextureStore.Snapshot {
        textureStore.update(from: SceneMediaThumbnailInbox.shared.latest())
        return textureStore.snapshot()
    }

    func encodeTransition(
        media: SceneMediaThumbnailTextureStore.Snapshot,
        sceneTime: Double,
        commandBuffer: MTLCommandBuffer
    ) -> [Int: SceneTextureProviderPublication] {
        transitionRenderer?.encode(
            program: program,
            resources: transitionTextures,
            media: media,
            sceneTime: sceneTime,
            commandBuffer: commandBuffer
        ) ?? [:]
    }
}
