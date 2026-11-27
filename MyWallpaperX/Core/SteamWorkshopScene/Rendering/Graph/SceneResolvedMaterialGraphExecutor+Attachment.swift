import Metal

extension SceneResolvedMaterialGraphExecutor {
    func prepareCapturedMaterial(
        program: SceneResolvedMaterialProgram,
        material: SceneResolvedMaterialExecutionCapabilityCatalog.MaterialCapability,
        capture: SceneGraphResourcePassEncoder.PreparedCommand,
        target: MTLTexture
    ) -> (SceneGraphResourcePassEncoder.PreparedCommand, SceneResolvedMaterialPassEncoder.PreparedPass)? {
        guard material.attachmentStorage == .color, target.pixelFormat == material.targetFormat.metalPixelFormat,
              let attachment = program.frontendProgram.localAttachmentOverwrite,
              let source = program.textureSlots[attachment.sourceSlot]?.resource.publication.candidate,
              source.texture === capture.writtenTexture, source.uvTransform == .identity,
              source.texture.width == target.width, source.texture.height == target.height,
              source.texture.pixelFormat == target.pixelFormat,
              !attachment.physicalTextureSlots.contains(where: {
                  program.textureSlots[$0]?.resource.publication.texture === source.texture
              }),
              let redirected = capture.retargetingPlainSourceCapture(toEquivalentTarget: target),
              let pass = materialEncoder.prepareCaptureTail(program: program, target: target) else { return nil }
        return (redirected, pass)
    }

    func prepareMaterialPass(
        program: SceneResolvedMaterialProgram,
        material: SceneResolvedMaterialExecutionCapabilityCatalog.MaterialCapability,
        target: MTLTexture,
        descriptor: State.ResourceDescriptor?,
        partialCoverage: Bool = false
    ) -> Result<SceneResolvedMaterialPassEncoder.PreparedPass,
        SceneResolvedMaterialPassEncoder.PreparationFailure>? {
        let matches = switch (material.targetFormat, descriptor?.format) {
        case (.r8, .r8),
             (.rg88, .rg88),
             (.r16f, .r16f),
             (.rg1616f, .rg1616f),
             (.rgbaBackbuffer, .rgbaBackbuffer),
             (.rgba8888, .rgba8888),
             (.rgba16f, .rgba16f),
             (.rgba16f, nil),
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
            attachmentStorage: material.attachmentStorage,
            partialCoverage: partialCoverage
        )
    }
}
