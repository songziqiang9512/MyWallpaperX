import Foundation

nonisolated enum SceneAuthoredShaderMetalEmitter {
    struct Output {
        let source: String?
        let diagnostics: [SceneAuthoredShaderFrontendDiagnostic]
    }

    private struct Context {
        let unit: SceneAuthoredShaderSyntaxUnit
        let functionNames: Set<String>
        let uniformNames: Set<String>
        let varyingNames: Set<String>
        let attributeNames: Set<String>
        let texturesByName: [String: SceneAuthoredShaderProgram.TextureBinding]
        let straightAlphaTextureSlot: Int?
    }

    static func emit(
        vertex: SceneAuthoredShaderSyntaxUnit,
        fragment: SceneAuthoredShaderSyntaxUnit,
        uniforms: [(String, SceneAuthoredShaderValueType)],
        uniformLayout: SceneAuthoredShaderUniformLayout,
        textures: [SceneAuthoredShaderProgram.TextureBinding],
        varyings: [(String, SceneAuthoredShaderValueType)],
        colorTransfer: SceneShaderColorTransfer
    ) -> Output {
        let defineResult = mergedDefines(vertex.defines, fragment.defines)
        guard let defines = defineResult.defines else {
            return Output(source: nil, diagnostics: defineResult.diagnostics)
        }
        for unit in [vertex, fragment] {
            guard let main = unit.functions.first(where: { $0.name == "main" }),
                  main.returnType == "void",
                  main.parameterRange.isEmpty else {
                return Output(source: nil, diagnostics: [.init(
                    code: .unsupportedDeclaration,
                    message: "Shader main must have the signature void main().",
                    stage: unit.stage,
                    line: unit.functions.first(where: { $0.name == "main" })?.line,
                    column: nil
                )])
            }
        }
        let texturesByName = Dictionary(uniqueKeysWithValues: textures.map { ($0.name, $0) })
        let uniformNames = Set(uniforms.map(\.0))
        let varyingNames = Set(varyings.map(\.0))
        let vertexContext = Context(
            unit: vertex,
            functionNames: Set(vertex.functions.map(\.name)),
            uniformNames: uniformNames,
            varyingNames: varyingNames,
            attributeNames: Set(vertex.declarations.filter {
                $0.storage == .attribute
            }.map(\.name)),
            texturesByName: texturesByName,
            straightAlphaTextureSlot: nil
        )
        let straightAlphaTextureSlot: Int?
        if case let .straightAlpha(slot) = colorTransfer { straightAlphaTextureSlot = slot }
        else { straightAlphaTextureSlot = nil }
        let fragmentContext = Context(
            unit: fragment,
            functionNames: Set(fragment.functions.map(\.name)),
            uniformNames: uniformNames,
            varyingNames: varyingNames,
            attributeNames: [],
            texturesByName: texturesByName,
            straightAlphaTextureSlot: straightAlphaTextureSlot
        )
        let vertexEmission = emitStage(context: vertexContext, textures: textures)
        let fragmentEmission = emitStage(context: fragmentContext, textures: textures)
        let diagnostics = vertexEmission.diagnostics + fragmentEmission.diagnostics
        guard let vertexCode = vertexEmission.source,
              let fragmentCode = fragmentEmission.source,
              diagnostics.isEmpty else {
            return Output(source: nil, diagnostics: diagnostics)
        }
        let source = [
            SceneAuthoredShaderMetalSource.prelude(
                defines: defines,
                colorTransfer: colorTransfer
            ),
            SceneAuthoredShaderMetalSource.uniformStruct(layout: uniformLayout),
            SceneAuthoredShaderMetalSource.stageStructs(varyings: varyings),
            vertexCode,
            fragmentCode,
            SceneAuthoredShaderMetalSource.vertexWrapper(textures: textures),
            SceneAuthoredShaderMetalSource.fragmentWrapper(
                textures: textures,
                colorTransfer: colorTransfer
            ),
        ].joined(separator: "\n\n")
        return Output(source: source, diagnostics: [])
    }

    private struct StageEmission {
        let source: String?
        let diagnostics: [SceneAuthoredShaderFrontendDiagnostic]
    }

    private static func emitStage(
        context: Context,
        textures: [SceneAuthoredShaderProgram.TextureBinding]
    ) -> StageEmission {
        let omitted = context.unit.declarations.map(\.range)
            + context.unit.functions.map { $0.headerRange.lowerBound..<$0.bodyRange.upperBound }
        let globalIndices = context.unit.tokens.indices.filter { index in
            !omitted.contains(where: { $0.contains(index) })
        }
        if let token = globalIndices.map({ context.unit.tokens[$0] }).first(where: {
            context.uniformNames.contains($0.text)
                || context.varyingNames.contains($0.text)
                || context.attributeNames.contains($0.text)
        }) {
            return StageEmission(source: nil, diagnostics: [.init(
                code: .unsupportedDeclaration,
                message: "Stage globals cannot be initialized from runtime declarations.",
                stage: context.unit.stage,
                line: token.line,
                column: token.column
            )])
        }
        let globalSource = emitTokens(
            globalIndices.map { context.unit.tokens[$0] },
            context: context,
            textures: textures,
            insertsContextIntoCalls: false
        ).source
        var functions: [String] = []
        for function in context.unit.functions {
            let parameters = Array(context.unit.tokens[function.parameterRange])
            let body = Array(context.unit.tokens[function.bodyRange])
            let emittedParameters = emitTokens(
                parameters,
                context: context,
                textures: textures,
                insertsContextIntoCalls: false
            )
            let emittedBody = emitTokens(
                body,
                context: context,
                textures: textures,
                insertsContextIntoCalls: true
            )
            let diagnostics = emittedParameters.diagnostics + emittedBody.diagnostics
            guard diagnostics.isEmpty else {
                return StageEmission(source: nil, diagnostics: diagnostics)
            }
            guard function.returnType == "void"
                    || SceneAuthoredShaderValueType(authoredName: function.returnType) != nil else {
                return StageEmission(source: nil, diagnostics: [.init(
                    code: .unsupportedType,
                    message: "Function '\(function.name)' has unsupported return type '\(function.returnType)'.",
                    stage: context.unit.stage,
                    line: function.line,
                    column: nil
                )])
            }
            let returnType = translatedIdentifier(function.returnType)
            let contextParameters = contextParameterList(
                stage: context.unit.stage,
                textures: textures
            )
            let authoredParameters = emittedParameters.source.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            let separator = authoredParameters.isEmpty ? "" : ", "
            functions.append(
                "\(returnType) \(functionPrefix(context.unit.stage))\(function.name)"
                    + "(\(contextParameters)\(separator)\(authoredParameters)) \(emittedBody.source)"
            )
        }
        return StageEmission(
            source: [globalSource, functions.joined(separator: "\n\n")]
                .filter { !$0.isEmpty }
                .joined(separator: "\n\n"),
            diagnostics: []
        )
    }

    private struct TokenEmission {
        let source: String
        let diagnostics: [SceneAuthoredShaderFrontendDiagnostic]
    }

    private static func emitTokens(
        _ tokens: [SceneAuthoredShaderToken],
        context: Context,
        textures: [SceneAuthoredShaderProgram.TextureBinding],
        insertsContextIntoCalls: Bool
    ) -> TokenEmission {
        var output: [String] = []
        var diagnostics: [SceneAuthoredShaderFrontendDiagnostic] = []
        var index = 0
        while index < tokens.count {
            let token = tokens[index]
            if ["texSample2D", "texture2D"].contains(token.text),
               index + 1 < tokens.count, tokens[index + 1].text == "(" {
                let sample = emitTextureSample(
                    tokens: tokens,
                    start: index,
                    context: context,
                    textures: textures
                )
                if let source = sample.source, let nextIndex = sample.nextIndex {
                    output.append(source)
                    index = nextIndex
                    continue
                }
                diagnostics.append(sample.diagnostic ?? .init(
                    code: .unsupportedSampler,
                    message: "Texture sample expression is unsupported.",
                    stage: context.unit.stage,
                    line: token.line,
                    column: token.column
                ))
                break
            }
            let isUserCall = insertsContextIntoCalls
                && context.functionNames.contains(token.text)
                && index + 1 < tokens.count
                && tokens[index + 1].text == "("
            output.append(translatedToken(token, context: context))
            if isUserCall {
                output.append("(")
                output.append(contextArguments(stage: context.unit.stage, textures: textures))
                if index + 2 < tokens.count, tokens[index + 2].text != ")" {
                    output.append(",")
                }
                index += 2
            } else {
                index += 1
            }
        }
        return TokenEmission(source: output.joined(separator: " "), diagnostics: diagnostics)
    }

    private static func translatedToken(
        _ token: SceneAuthoredShaderToken,
        context: Context
    ) -> String {
        if token.text == "in" { return "" }
        if context.uniformNames.contains(token.text) { return "mwxUniforms.\(token.text)" }
        if context.varyingNames.contains(token.text) {
            return context.unit.stage == .vertex
                ? "mwxOutput.\(token.text)"
                : "mwxInput.\(token.text)"
        }
        if context.attributeNames.contains(token.text) { return "mwxAttributes.\(token.text)" }
        if token.text == "gl_Position" { return "mwxOutput.position" }
        if token.text == "gl_FragColor" { return "mwxFragColor" }
        if context.functionNames.contains(token.text) {
            return functionPrefix(context.unit.stage) + token.text
        }
        if let texture = context.texturesByName[token.text] {
            return "mwxTexture\(texture.slot)"
        }
        return translatedIdentifier(token.text)
    }

    private static func translatedIdentifier(_ value: String) -> String {
        if let type = SceneAuthoredShaderValueType(authoredName: value) { return type.metalName }
        if value == "mod" { return "fmod" }
        return value
    }

    private struct SampleEmission {
        let source: String?
        let nextIndex: Int?
        let diagnostic: SceneAuthoredShaderFrontendDiagnostic?
    }

    private static func emitTextureSample(
        tokens: [SceneAuthoredShaderToken],
        start: Int,
        context: Context,
        textures: [SceneAuthoredShaderProgram.TextureBinding]
    ) -> SampleEmission {
        guard let close = matchingParenthesis(tokens: tokens, opening: start + 1),
              let comma = topLevelComma(tokens: tokens, range: (start + 2)..<close),
              comma == start + 3,
              let texture = context.texturesByName[tokens[start + 2].text] else {
            return .init(source: nil, nextIndex: nil, diagnostic: nil)
        }
        let coordinateTokens = Array(tokens[(comma + 1)..<close])
        let coordinate = emitTokens(
            coordinateTokens,
            context: context,
            textures: textures,
            insertsContextIntoCalls: true
        )
        guard coordinate.diagnostics.isEmpty else {
            return .init(source: nil, nextIndex: nil, diagnostic: coordinate.diagnostics.first)
        }
        let sample = "mwxTexture\(texture.slot).sample(mwxSampler\(texture.slot), \(coordinate.source))"
        let source = context.straightAlphaTextureSlot == texture.slot
            ? "mwxUnpremultiply(\(sample))"
            : sample
        return .init(
            source: source,
            nextIndex: close + 1,
            diagnostic: nil
        )
    }

    private static func contextParameterList(
        stage: SceneShaderContract.StageKind,
        textures: [SceneAuthoredShaderProgram.TextureBinding]
    ) -> String {
        var parameters = stage == .vertex
            ? [
                "SceneAuthoredVertexAttributes mwxAttributes",
                "thread SceneAuthoredVertexOutput &mwxOutput",
                "constant SceneAuthoredUniforms &mwxUniforms",
            ]
            : [
                "SceneAuthoredFragmentInput mwxInput",
                "thread float4 &mwxFragColor",
                "constant SceneAuthoredUniforms &mwxUniforms",
            ]
        for texture in textures {
            parameters.append("texture2d<float> mwxTexture\(texture.slot)")
            parameters.append("sampler mwxSampler\(texture.slot)")
        }
        return parameters.joined(separator: ", ")
    }

    private static func contextArguments(
        stage: SceneShaderContract.StageKind,
        textures: [SceneAuthoredShaderProgram.TextureBinding]
    ) -> String {
        var arguments = stage == .vertex
            ? ["mwxAttributes", "mwxOutput", "mwxUniforms"]
            : ["mwxInput", "mwxFragColor", "mwxUniforms"]
        for texture in textures {
            arguments.append("mwxTexture\(texture.slot)")
            arguments.append("mwxSampler\(texture.slot)")
        }
        return arguments.joined(separator: ", ")
    }

    private static func functionPrefix(_ stage: SceneShaderContract.StageKind) -> String {
        stage == .vertex ? "mwxV_" : "mwxF_"
    }

    private static func mergedDefines(
        _ first: [String: String],
        _ second: [String: String]
    ) -> (defines: [String: String]?, diagnostics: [SceneAuthoredShaderFrontendDiagnostic]) {
        var result = first
        for (name, value) in second {
            if let existing = result[name], existing != value {
                return (nil, [.init(
                    code: .malformedDefine,
                    message: "Shader stages define '\(name)' with conflicting values.",
                    stage: nil,
                    line: nil,
                    column: nil
                )])
            }
            result[name] = value
        }
        return (result, [])
    }

    private static func matchingParenthesis(
        tokens: [SceneAuthoredShaderToken],
        opening: Int
    ) -> Int? {
        var depth = 0
        for index in opening..<tokens.count {
            if tokens[index].text == "(" { depth += 1 }
            if tokens[index].text == ")" {
                depth -= 1
                if depth == 0 { return index }
            }
        }
        return nil
    }

    private static func topLevelComma(
        tokens: [SceneAuthoredShaderToken],
        range: Range<Int>
    ) -> Int? {
        var depth = 0
        for index in range {
            if ["(", "["].contains(tokens[index].text) { depth += 1 }
            if [")", "]"].contains(tokens[index].text) { depth -= 1 }
            if depth == 0, tokens[index].text == "," { return index }
        }
        return nil
    }
}
