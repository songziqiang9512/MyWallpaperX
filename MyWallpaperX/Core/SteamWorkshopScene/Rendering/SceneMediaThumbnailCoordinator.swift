import Metal

/// Per-surface owner for the current decoded media provider.
final class SceneMediaThumbnailCoordinator {
    let program: SceneBaseMaterialProviderBindingProgram

    private let textureStore: SceneMediaThumbnailTextureStore

    init(
        program: SceneBaseMaterialProviderBindingProgram,
        textureUploadCommandQueue: SceneTextureUploadCommandQueue = .init(),
        device: MTLDevice
    ) {
        self.program = program
        textureStore = SceneMediaThumbnailTextureStore(
            device: device,
            textureUploadCommandQueue: textureUploadCommandQueue
        )
    }

    func update(
        from input: SceneMediaThumbnailInbox.Snapshot
    ) -> SceneMediaThumbnailTextureStore.Snapshot {
        textureStore.update(from: input)
        return textureStore.snapshot()
    }

    func snapshot() -> SceneMediaThumbnailTextureStore.Snapshot {
        textureStore.snapshot()
    }

    func prepareFrame() -> SceneMediaThumbnailTextureStore.Snapshot {
        textureStore.prepareFrame()
    }

    func commitPreparedFrame() {
        textureStore.commitPreparedFrame()
    }

    func discardPreparedFrame() {
        textureStore.discardPreparedFrame()
    }
}
