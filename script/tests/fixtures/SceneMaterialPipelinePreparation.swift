import Metal

// Standalone draw gates perform the same preparation -> frame ordering as
// the product. They still exercise the real compiler, cache and pass encoder.
@discardableResult
func prepareMaterialPipeline(
    _ program: SceneResolvedMaterialProgram,
    encoder: SceneResolvedMaterialPassEncoder,
    target: MTLTexture,
    attachmentStorage: SceneResolvedMaterialAttachmentKind = .color,
    partialCoverage: Bool = false
) -> SceneResolvedMaterialPassEncoder.WarmupReport {
    let output = SceneResolvedMaterialAttachmentStorage.storedOutput(
        program.outputContract, attachmentStorage: attachmentStorage,
        partialCoverage: partialCoverage)!
    let plan = SceneResolvedMaterialPassEncoder.WarmupPlan(
        identity: "standalone-material", prepared: program.preparedAssembly,
        pixelFormat: target.pixelFormat, sampleCount: target.sampleCount,
        writeMask: SceneResolvedMaterialAttachmentStorage.writeMask(for: output.content),
        device: encoder.device)!
    return encoder.warmup([plan])
}
