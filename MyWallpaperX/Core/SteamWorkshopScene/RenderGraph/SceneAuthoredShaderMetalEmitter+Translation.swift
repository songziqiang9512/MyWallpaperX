nonisolated extension SceneAuthoredShaderMetalEmitter {
    static func translatedToken(
        _ token: SceneAuthoredShaderToken,
        context: Context
    ) -> String {
        if token.text == "in" { return "" }
        if token.text == "inout" { return "thread" }
        if let maximum = context.unit.boundedLoopUniformReferences[token],
           let field = context.uniformNames[token.text] {
            return "clamp(mwxUniforms.\(field), 0.0, \(maximum).0)"
        }
        if let field = context.uniformNames[token.text] { return "mwxUniforms.\(field)" }
        if context.varyingNames.contains(token.text) {
            return context.unit.stage == .vertex
                ? "mwxOutput.\(token.text)"
                : "mwxInput.\(token.text)"
        }
        if context.attributeNames.contains(token.text) { return "mwxAttributes.\(token.text)" }
        if token.text == "gl_Position" { return "mwxOutput.position" }
        if token.text == "gl_FragColor" { return "mwxFragColor" }
        if context.functionNames.contains(token.text) {
            return SceneAuthoredShaderMetalSource.functionPrefix(context.unit.stage) + token.text
        }
        if let texture = context.texturesByName[token.text] {
            return "mwxTexture\(texture.slot)"
        }
        return translatedIdentifier(token.text)
    }

    static func translatedIdentifier(_ value: String) -> String {
        if let type = SceneAuthoredShaderValueType(authoredName: value) { return type.metalName }
        if value == "mod" { return "fmod" }
        if value == "inverse" { return "mwxInverseFloat3x3" }
        return value
    }
}
