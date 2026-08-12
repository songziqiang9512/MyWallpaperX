import Metal

/// Keeps color-framebuffer and single-channel graph attachment contracts
/// distinct before pipeline compilation or command encoding.
nonisolated enum SceneResolvedMaterialAttachmentStorage {
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
        content == .scalarRedUnorm ? .red : .all
    }
}

nonisolated extension SceneResolvedMaterialAttachmentKind {
    func storedContent(
        fragmentOutput: SceneShaderColorRepresentation
    ) -> SceneTextureContent {
        switch self {
        case .color: .color(.resolved(fragmentOutput))
        case .scalarRedUnorm: .scalarRedUnorm
        }
    }
}
