import Metal

extension SceneResolvedMaterialGraphExecutor {
    func prepareMaterialPass(
        program: SceneResolvedMaterialProgram,
        material: SceneResolvedMaterialExecutionCapabilityCatalog.MaterialCapability,
        target: MTLTexture,
        descriptor: State.ResourceDescriptor?
    ) -> Result<SceneResolvedMaterialPassEncoder.PreparedPass,
        SceneResolvedMaterialPassEncoder.PreparationFailure>? {
        let matches = switch (material.attachmentStorage, descriptor?.format) {
        case (.scalarRedUnorm, .r8),
             (.color, .rgbaBackbuffer),
             (.color, .rgba8888),
             (.color, nil):
            true
        default:
            false
        }
        guard matches else { return nil }
        return materialEncoder.prepareResult(
            program: program,
            target: target,
            attachmentStorage: material.attachmentStorage
        )
    }
}
