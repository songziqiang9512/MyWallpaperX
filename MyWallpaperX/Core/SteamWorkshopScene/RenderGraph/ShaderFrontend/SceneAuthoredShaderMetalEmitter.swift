import Foundation

nonisolated enum SceneAuthoredShaderMetalEmitter {
    struct Output {
        let source: String?
        let diagnostics: [SceneAuthoredShaderFrontendDiagnostic]
    }

    struct Context {
        let unit: SceneAuthoredShaderSyntaxUnit
        let functionNames: Set<String>
        let uniformNames: [String: String]
        let varyingNames: Set<String>
        let varyingArrayCounts: [String: Int]
        let attributeNames: Set<String>
        let texturesByName: [String: SceneAuthoredShaderProgram.TextureBinding]
        let globalReferenceTokens: Set<SceneAuthoredShaderToken>
        let unpremultipliedTextureSlot: Int?
        let omittedStatementRanges: [Range<Int>]
    }

    static func emit(
        vertex: SceneAuthoredShaderSyntaxUnit,
        fragment: SceneAuthoredShaderSyntaxUnit,
        uniforms: [SceneAuthoredShaderUniformDeclaration],
        uniformLayout: SceneAuthoredShaderUniformLayout,
        textures: [SceneAuthoredShaderProgram.TextureBinding],
        varyings: [(String, SceneAuthoredShaderValueType, Int?)],
        omittedVertexStatementRanges: [Range<Int>],
        colorTransfer: SceneShaderColorTransfer
    ) -> Output {
        let defineResult = SceneAuthoredShaderMetalSource.mergedDefines(
            vertex.defines,
            fragment.defines
        )
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
        let vertexUniformNames = SceneAuthoredShaderUniformDeclaration.fieldNames(in: uniforms, for: .vertex)
        let fragmentUniformNames = SceneAuthoredShaderUniformDeclaration.fieldNames(in: uniforms, for: .fragment)
        let varyingNames = Set(varyings.map(\.0))
        let varyingArrayCounts: [String: Int] = Dictionary(uniqueKeysWithValues:
            varyings.compactMap { varying in
                varying.2.map { (varying.0, $0) }
            }
        )
        let vertexContext = Context(
            unit: vertex,
            functionNames: Set(vertex.functions.map(\.name)),
            uniformNames: vertexUniformNames,
            varyingNames: varyingNames,
            varyingArrayCounts: varyingArrayCounts,
            attributeNames: Set(vertex.declarations.filter {
                $0.storage == .attribute
            }.map(\.name)),
            texturesByName: texturesByName,
            globalReferenceTokens:
                SceneAuthoredShaderGlobalReferenceAnalyzer.referenceTokens(in: vertex),
            unpremultipliedTextureSlot: nil,
            omittedStatementRanges: omittedVertexStatementRanges
        )
        let unpremultipliedTextureSlot: Int?
        switch colorTransfer {
        case let .straightAlphaPreserving(slot), let .straightAlpha(slot),
             let .straightAlphaUNorm(slot), let .independentAlphaSignal(slot):
            unpremultipliedTextureSlot = slot
        case let .independentAlphaSignalCompositing(_, colorSlot):
            unpremultipliedTextureSlot = colorSlot
        default:
            unpremultipliedTextureSlot = nil
        }
        let fragmentContext = Context(
            unit: fragment,
            functionNames: Set(fragment.functions.map(\.name)),
            uniformNames: fragmentUniformNames,
            varyingNames: varyingNames,
            varyingArrayCounts: varyingArrayCounts,
            attributeNames: [],
            texturesByName: texturesByName,
            globalReferenceTokens:
                SceneAuthoredShaderGlobalReferenceAnalyzer.referenceTokens(in: fragment),
            unpremultipliedTextureSlot: unpremultipliedTextureSlot,
            omittedStatementRanges: []
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
            [vertex, fragment].contains(where: {
                SceneAuthoredShaderFunctionSemantics.usesFloat3x3Inverse($0)
            }) ? SceneAuthoredShaderMetalSource.float3x3InverseHelper : "",
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
            context.uniformNames[$0.text] != nil
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
            insertsContextIntoCalls: false,
            programScope: true
        ).source
        var functions: [String] = []
        for (functionIndex, function) in context.unit.functions.enumerated() {
            let parameters = Array(context.unit.tokens[function.parameterRange])
            let body = function.bodyRange.compactMap { index in
                context.omittedStatementRanges.contains(where: { $0.contains(index) })
                    ? nil
                    : context.unit.tokens[index]
            }
            let emittedParameters = emitTokens(
                parameters,
                context: context,
                textures: textures,
                insertsContextIntoCalls: false,
                constantArrayParameterNames:
                    context.unit.constantParameterArraysByFunctionIndex[functionIndex] ?? [],
                mutableParameterNames: SceneAuthoredShaderFunctionSemantics
                    .mutableParameterNames(for: function, unit: context.unit)
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
            let contextParameters = SceneAuthoredShaderMetalSource.contextParameterList(
                stage: context.unit.stage,
                textures: textures
            )
            let authoredParameters = emittedParameters.source.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            let separator = authoredParameters.isEmpty ? "" : ", "
            functions.append(
                "\(returnType) \(SceneAuthoredShaderMetalSource.functionPrefix(context.unit.stage))\(function.name)"
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
        insertsContextIntoCalls: Bool,
        constantArrayParameterNames: Set<String> = [],
        mutableParameterNames: Set<String> = [],
        programScope: Bool = false
    ) -> TokenEmission {
        var output: [String] = []
        var diagnostics: [SceneAuthoredShaderFrontendDiagnostic] = []
        let narrowingBoundaries = SceneAuthoredShaderVectorConversion.assignmentBoundaries(
            in: tokens, unit: context.unit)
        var index = 0
        while index < tokens.count {
            let token = tokens[index]
            if let count = narrowingBoundaries.starts[index] {
                output.append(String(repeating: "(", count: count))
            }
            if let suffixes = narrowingBoundaries.ends[index] {
                output.append(suffixes.map { ").\($0)" }.joined())
            }
            if programScope, token.text == "const" {
                output.append("constant")
                index += 1
                continue
            }
            if context.globalReferenceTokens.contains(token),
               let reference = SceneAuthoredShaderVaryingArrayEmitter.reference(
                tokens: tokens,
                index: index,
                arrayCounts: context.varyingArrayCounts,
                stage: context.unit.stage
            ) {
                guard let source = reference.source,
                      let nextIndex = reference.nextIndex else {
                    diagnostics.append(reference.diagnostic!)
                    break
                }
                output.append(source)
                index = nextIndex
                continue
            }
            if token.text == "float",
               index + 2 < tokens.count,
               constantArrayParameterNames.contains(tokens[index + 1].text),
               tokens[index + 2].text == "[" {
                output.append("constant")
            }
            if isTextureSampleBuiltIn(token.text, functionNames: context.functionNames),
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
            if let moduloTarget = SceneAuthoredShaderVectorConversion
                .floatingModuloTarget(
                    at: index,
                    in: tokens,
                    unit: context.unit
                ), let left = output.popLast() {
                let right = translatedToken(tokens[index + 1], context: context)
                let modulo = "fmod(float(\(left)), float(\(right)))"
                output.append(moduloTarget == .float
                    ? modulo
                    : "\(moduloTarget.metalName)(\(modulo))")
                index += 2
                continue
            }
            let isUserCall = insertsContextIntoCalls
                && context.functionNames.contains(token.text)
                && index + 1 < tokens.count
                && tokens[index + 1].text == "("
            let rawTranslated = translatedToken(token, context: context)
            let translated = mutableParameterNames.contains(token.text)
                ? "&\(rawTranslated)"
                : rawTranslated
            if let suffix = SceneAuthoredShaderVectorConversion.suffix(
                forIdentifierAt: index,
                in: tokens,
                unit: context.unit
            ) {
                output.append("(\(translated)).\(suffix)")
            } else {
                output.append(translated)
            }
            if isUserCall {
                output.append("(")
                output.append(SceneAuthoredShaderMetalSource.contextArguments(
                    stage: context.unit.stage,
                    textures: textures
                ))
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
        guard let close = SceneAuthoredShaderVectorConversion.matchingParenthesis(
                  tokens: tokens,
                  opening: start + 1
              ),
              let arguments = textureSampleArguments(
                  tokens: tokens, opening: start + 1, closing: close),
              arguments.count == (tokens[start].text == "texSample2DLod" ? 3 : 2),
              arguments[0].count == 1,
              let texture = context.texturesByName[tokens[arguments[0].lowerBound].text]
        else {
            return .init(source: nil, nextIndex: nil, diagnostic: nil)
        }
        let coordinate = emitTokens(
            Array(tokens[arguments[1]]), context: context, textures: textures,
            insertsContextIntoCalls: true
        )
        guard coordinate.diagnostics.isEmpty else {
            return .init(source: nil, nextIndex: nil, diagnostic: coordinate.diagnostics.first)
        }
        var levelSource: String?
        if arguments.count == 3 {
            guard isStaticFloatLevel(arguments[2], tokens: tokens, unit: context.unit) else {
                return .init(source: nil, nextIndex: nil, diagnostic: nil)
            }
            let level = emitTokens(
                Array(tokens[arguments[2]]), context: context, textures: textures,
                insertsContextIntoCalls: true
            )
            guard level.diagnostics.isEmpty else {
                return .init(source: nil, nextIndex: nil, diagnostic: level.diagnostics.first)
            }
            levelSource = level.source
        }
        let level = levelSource.map { ", level(\($0))" } ?? ""
        let coordinateSuffix = SceneAuthoredShaderVectorConversion
            .suffixForTextureCoordinate(
                tokens: tokens,
                range: arguments[1],
                unit: context.unit
            )
        let coordinateSource = coordinateSuffix.map {
            "(\(coordinate.source)).\($0)"
        } ?? coordinate.source
        let sample = "mwxTexture\(texture.slot).sample(mwxSampler\(texture.slot), "
            + "\(coordinateSource)\(level))"
        let sampledSource = context.unpremultipliedTextureSlot == texture.slot
            ? "mwxUnpremultiply(\(sample))"
            : sample
        let suffix = SceneAuthoredShaderVectorConversion.suffixForTextureSample(
            tokens: tokens, start: start, closing: close)
        let source = suffix.map { "(\(sampledSource)).\($0)" } ?? sampledSource
        return .init(
            source: source,
            nextIndex: close + 1,
            diagnostic: nil
        )
    }
}
