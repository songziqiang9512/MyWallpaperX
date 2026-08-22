/// Single schema authority shared by first-variant compilation, per-frame
/// binding and Program identity validation.
nonisolated enum SceneResolvedMaterialHostUniformSchema {
    typealias Program = SceneResolvedMaterialProgram

    static func resolve(
        _ field: SceneAuthoredShaderUniformLayout.Field,
        activeTextureSlots: Set<Int>
    ) -> Program.HostUniform? {
        switch (field.authoredName, field.type) {
        case ("mwxRenderSize", .float2): .renderSize
        case ("g_ModelViewProjectionMatrix", .float4x4): .modelViewProjection
        case ("g_ModelViewProjectionMatrixInverse", .float4x4):
            .modelViewProjectionInverse
        case ("g_LayerModelMatrix", .float4x4): .layerModelMatrix
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
            textureTransform(field, activeTextureSlots: activeTextureSlots)
                ?? textureResolution(field, activeTextureSlots: activeTextureSlots)
                ?? audioSpectrum(field)
        }
    }

    private static func textureTransform(
        _ field: SceneAuthoredShaderUniformLayout.Field,
        activeTextureSlots: Set<Int>
    ) -> Program.HostUniform? {
        guard field.type == .float4,
              field.arrayCount == nil,
              field.stage == nil,
              field.name == field.authoredName,
              let value = SceneMaterialTextureTransformABI.component(
                  forFieldName: field.name
              ),
              activeTextureSlots.contains(value.slot) else { return nil }
        return .textureTransform(
            slot: value.slot,
            component: value.component
        )
    }

    private static func textureResolution(
        _ field: SceneAuthoredShaderUniformLayout.Field,
        activeTextureSlots: Set<Int>
    ) -> Program.HostUniform? {
        let name = field.authoredName
        guard field.type == .float4,
              name.hasPrefix("g_Texture"),
              name.hasSuffix("Resolution") else { return nil }
        let start = name.index(
            name.startIndex,
            offsetBy: "g_Texture".count
        )
        let end = name.index(
            name.endIndex,
            offsetBy: -"Resolution".count
        )
        guard start < end, let slot = Int(name[start ..< end]),
              activeTextureSlots.contains(slot) else { return nil }
        return .textureResolution(slot: slot)
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
