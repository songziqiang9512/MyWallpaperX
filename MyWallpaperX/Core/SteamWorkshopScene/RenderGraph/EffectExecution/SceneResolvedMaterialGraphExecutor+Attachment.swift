import Metal

extension SceneResolvedMaterialGraphExecutor {
    func prepareMaterialPass(
        program: SceneResolvedMaterialProgram,
        material: SceneResolvedMaterialExecutionCapabilityCatalog.MaterialCapability,
        target: MTLTexture,
        descriptor: State.ResourceDescriptor?
    ) -> Result<SceneResolvedMaterialPassEncoder.PreparedPass,
        SceneResolvedMaterialPassEncoder.PreparationFailure>? {
        let matches = switch (material.targetFormat, descriptor?.format) {
        case (.r8, .r8),
             (.rgbaBackbuffer, .rgbaBackbuffer),
             (.rgba8888, .rgba8888),
             (.rgbaBackbuffer, nil):
            true
        default:
            false
        }
        guard matches,
              target.pixelFormat == material.targetFormat.metalPixelFormat else {
            return nil
        }
        return materialEncoder.prepareResult(
            program: program,
            target: target,
            attachmentStorage: material.attachmentStorage
        )
    }
}
