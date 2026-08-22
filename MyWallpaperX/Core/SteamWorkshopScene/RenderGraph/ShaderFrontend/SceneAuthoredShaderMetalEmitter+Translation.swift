nonisolated extension SceneAuthoredShaderMetalEmitter {
    static func isTextureSampleBuiltIn(
        _ name: String,
        functionNames: Set<String>
    ) -> Bool {
        ["texSample2D", "texture2D"].contains(name)
            || (["texSample2DLod", "texture2DLod"].contains(name)
                && !functionNames.contains(name))
    }

    static func textureSampleArguments(
        tokens: [SceneAuthoredShaderToken],
        opening: Int,
        closing: Int
    ) -> [Range<Int>]? {
        guard opening < closing else { return nil }
        var arguments: [Range<Int>] = []
        var start = opening + 1
        var depth = 0
        for index in start...closing {
            let isEnd = index == closing
            if !isEnd, ["(", "["].contains(tokens[index].text) { depth += 1 }
            if !isEnd, [")", "]"].contains(tokens[index].text) { depth -= 1 }
            guard depth >= 0 else { return nil }
            guard isEnd || (depth == 0 && tokens[index].text == ",") else { continue }
            guard start < index else { return nil }
            arguments.append(start..<index)
            start = index + 1
        }
        return depth == 0 ? arguments : nil
    }

    static func isStaticFloatLevel(
        _ range: Range<Int>,
        tokens: [SceneAuthoredShaderToken],
        unit: SceneAuthoredShaderSyntaxUnit
    ) -> Bool {
        guard range.count == 1 else { return false }
        let token = tokens[range.lowerBound]
        if token.kind == .number { return true }
        guard token.kind == .identifier else { return false }
        var types = Set(unit.declarations.compactMap {
            $0.name == token.text
                ? SceneAuthoredShaderValueType(authoredName: $0.typeName)
                : nil
        })
        for index in 0..<range.lowerBound where index + 1 < tokens.count {
            guard tokens[index + 1].text == token.text,
                  let type = SceneAuthoredShaderValueType(
                      authoredName: tokens[index].text
                  ) else { continue }
            types.insert(type)
        }
        return types == [.float]
    }

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
        if context.globalReferenceTokens.contains(token),
           let field = context.uniformNames[token.text] {
            return "mwxUniforms.\(field)"
        }
        if context.globalReferenceTokens.contains(token),
           context.varyingNames.contains(token.text) {
            return context.unit.stage == .vertex
                ? "mwxOutput.\(token.text)"
                : "mwxInput.\(token.text)"
        }
        if context.globalReferenceTokens.contains(token),
           context.attributeNames.contains(token.text) {
            return "mwxAttributes.\(token.text)"
        }
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
