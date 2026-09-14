import Metal

/// Keeps color-framebuffer and preserved-channel graph attachment contracts
/// distinct before pipeline compilation or command encoding.
nonisolated enum SceneResolvedMaterialAttachmentStorage {
    struct StoredOutput {
        let content: SceneTextureContent
        let colorRepresentation: SceneShaderColorRepresentation?
    }

    static func acceptedColorOutput(
        _ resolution: SceneShaderColorRepresentationResolution
    ) -> SceneShaderColorRepresentation? {
        switch resolution {
        case .resolved(.opaque): return .opaque
        case .resolved(.premultipliedAlpha): return .premultipliedAlpha
        case .resolved(.independentAlphaSignal): return .independentAlphaSignal
        case .resolved(.straightAlpha), .unresolved: return nil
        }
    }

    static func target(
        _ target: MTLTexture,
        belongsTo device: MTLDevice,
        stores content: SceneTextureContent
    ) -> Bool {
        let formatMatchesContent: Bool
        switch (target.pixelFormat, content) {
        case (.r8Unorm, .scalarRedUnorm),
             (.rg8Unorm, .redGreenUnorm),
             (.r16Float, .scalarRedFloat16),
             (.rg16Float, .redGreenFloat16),
             (.rgba8Unorm, .data),
             (.bgra8Unorm, .data),
             (.bgra8Unorm, .color(.resolved)),
             (.rgba8Unorm, .color(.resolved)):
            formatMatchesContent = true
        default:
            formatMatchesContent = false
        }
        return formatMatchesContent
            && target.device.registryID == device.registryID
            && target.textureType == .type2D
            && target.width > 0
            && target.height > 0
            && target.mipmapLevelCount == 1
            && target.sampleCount == 1
            && target.usage.contains(.renderTarget)
            && target.usage.contains(.shaderRead)
    }

    static func writeMask(for content: SceneTextureContent) -> MTLColorWriteMask {
        switch content {
        case .scalarRedUnorm, .scalarRedFloat16: .red
        case .redGreenUnorm, .redGreenFloat16: [.red, .green]
        case .color, .data: .all
        }
    }

    static func storedOutput(
        _ outputContract: SceneResolvedMaterialProgram.OutputContract,
        attachmentStorage: SceneResolvedMaterialAttachmentKind
    ) -> StoredOutput? {
        switch (outputContract, attachmentStorage) {
        case let (.color(contract), .color):
            guard let representation = acceptedColorOutput(
                contract.fragmentOutput
            ) else { return nil }
            return .init(
                content: .color(.resolved(representation)),
                colorRepresentation: representation
            )
        case (.scalarRedUnorm, .scalarRedUnorm):
            return .init(
                content: .scalarRedUnorm,
                colorRepresentation: nil
            )
        case (.redGreenUnorm, .redGreenUnorm):
            return .init(
                content: .redGreenUnorm,
                colorRepresentation: nil
            )
        case (.scalarRedFloat16, .scalarRedFloat16):
            return .init(
                content: .scalarRedFloat16,
                colorRepresentation: nil
            )
        case (.redGreenFloat16, .redGreenFloat16):
            return .init(
                content: .redGreenFloat16,
                colorRepresentation: nil
            )
        case (.preservedRGBAUnorm, .preservedRGBAUnorm):
            return .init(content: .data, colorRepresentation: nil)
        default:
            return nil
        }
    }
}
