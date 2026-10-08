/// Single schema authority shared by first-variant compilation, per-frame
/// binding and Program identity validation.
nonisolated enum SceneResolvedMaterialHostUniformSchema {
    typealias Program = SceneResolvedMaterialProgram

    static func resolve(
        _ field: SceneAuthoredShaderUniformLayout.Field,
        activeTextureSlots: Set<Int>
    ) -> Program.HostUniform? {
        switch (field.authoredName, field.type) {
        case (SceneShaderColorBoundary.uniformName, .uint) where field.arrayCount == nil:
            .premultipliedColorInputMask
        case ("mwxRenderSize", .float2): .renderSize
        case ("g_ModelViewProjectionMatrix", .float4x4): .modelViewProjection
        case ("g_ModelViewProjectionMatrixInverse", .float4x4):
            .modelViewProjectionInverse
        case ("g_LayerModelMatrix", .float4x4): .layerModelMatrix
        case ("g_EffectModelViewProjectionMatrix", .float4x4):
            .effectModelViewProjection
        case ("g_EffectTextureProjectionMatrix", .float4x4):
            .effectTextureProjectionMatrix
        case ("g_EffectTextureProjectionMatrixInverse", .float4x4):
            .effectTextureProjectionMatrixInverse
        case ("g_Time", .float): .time
        case ("g_Daytime", .float): .dayTime
        case ("g_Frametime", .float): .frameTime
        case ("g_PointerPosition", .float2): .pointerPosition
        case ("g_PointerPositionLast", .float2): .pointerPositionLast
        case ("g_PointerState", .float4): .pointerState
        case ("g_ParallaxPosition", .float2): .parallaxPosition
        case ("g_Screen", .float3): .screen
        case ("g_TexelSize", .float2):
            .texelSize(scaleBitPattern: Double(1).bitPattern)
        case ("g_TexelSizeHalf", .float2):
            .texelSize(scaleBitPattern: Double(0.5).bitPattern)
        default:
            textureUniform(field, activeTextureSlots: activeTextureSlots)
                ?? audioSpectrum(field)
        }
    }

    private static func textureUniform(
        _ field: SceneAuthoredShaderUniformLayout.Field,
        activeTextureSlots: Set<Int>
    ) -> Program.HostUniform? {
        let name = field.authoredName
        guard field.arrayCount == nil,
              let slot = textureSlotPrefix(name),
              activeTextureSlots.contains(slot) else { return nil }
        switch (name, field.type) {
        case ("g_Texture\(slot)Resolution", .float4):
            return .textureResolution(slot: slot)
        case ("g_Texture\(slot)Rotation", .float4):
            return .textureRotation(slot: slot)
        case ("g_Texture\(slot)Translation", .float2):
            return .textureTranslation(slot: slot)
        default:
            return nil
        }
    }

    /// A malformed public companion cannot become an authored static/dynamic
    /// uniform merely because its type or active binding failed resolution.
    /// Resolution retains its separate neutral/self-composite contracts.
    static func requiresTextureCompanionHost(_ name: String) -> Bool {
        guard let slot = textureSlotPrefix(name) else { return false }
        return name == "g_Texture\(slot)Rotation"
            || name == "g_Texture\(slot)Translation"
    }

    private static func textureSlotPrefix(_ name: String) -> Int? {
        guard name.hasPrefix("g_Texture"),
              let slot = Int(name.dropFirst("g_Texture".count).prefix(1)),
              (0 ..< 8).contains(slot) else { return nil }
        return slot
    }

    private static func audioSpectrum(
        _ field: SceneAuthoredShaderUniformLayout.Field
    ) -> Program.HostUniform? {
        guard field.type == .float,
              let count = field.arrayCount,
              [16, 32, 64].contains(count) else { return nil }
        switch field.authoredName {
        case "g_AudioSpectrum\(count)Left": return .audioSpectrumLeft(count: count)
        case "g_AudioSpectrum\(count)Right": return .audioSpectrumRight(count: count)
        default:
            return nil
        }
    }
}
