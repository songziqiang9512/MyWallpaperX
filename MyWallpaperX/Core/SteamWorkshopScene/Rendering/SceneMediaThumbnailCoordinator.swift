import Metal

/// Per-surface owner for the current decoded media provider.
final class SceneMediaThumbnailCoordinator {
    let program: SceneMediaThumbnailBindingProgram

    private let textureStore: SceneMediaThumbnailTextureStore

    init(
        program: SceneMediaThumbnailBindingProgram,
        device: MTLDevice
    ) {
        self.program = program
        textureStore = SceneMediaThumbnailTextureStore(device: device)
    }

    func update(
        from input: SceneMediaThumbnailInbox.Snapshot
    ) -> SceneMediaThumbnailTextureStore.Snapshot {
        textureStore.update(from: input)
        return textureStore.snapshot()
    }
}
