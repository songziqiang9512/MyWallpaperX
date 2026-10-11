import Foundation

/// Adapts proven direct user-function arguments in the shared preparation chain.
nonisolated enum SceneGenericShaderDirectFunctionVectorArgumentNormalizer {
    typealias Shape = SceneGenericShaderSourceNormalizer.Shape

    private struct Parameter {
        let width: Int?
        let isScalarFloat: Bool
        let isReadOnly: Bool
    }

    /// Uses the shared syntax graph without admitting its loops for bounded
    /// execution. Unknown expressions and overloads remain fail-closed.
    static func rewriteUsingTypeSyntax(
        _ source: String,
        stage: SceneShaderContract.StageKind
    ) -> String {
        let normalized = source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let analysisSource = normalized.components(separatedBy: "\n").map { line in
            line.trimmingCharacters(in: .whitespaces).hasPrefix("#version")
                ? "" : line
        }.joined(separator: "\n")
        let lexer = SceneAuthoredShaderLexer.lex(source: analysisSource, stage: stage)
        let analysis = SceneAuthoredShaderSyntaxAnalyzer.analyzeForTypeConversions(
            lexerOutput: lexer,
            stage: stage
        )
        guard analysis.diagnostics.isEmpty, let unit = analysis.unit else {
            return normalized
        }

        let lineStarts = sourceLineStarts(normalized)
        var edits = unit.tokens.indices.compactMap { index -> (Int, Int, String)? in
            let token = unit.tokens[index]
            guard token.kind == .identifier,
                  let suffix = SceneAuthoredShaderVectorConversion.suffix(
                      forIdentifierAt: index,
                      in: unit.tokens,
                      unit: unit
                  ), token.line > 0, token.line <= lineStarts.count else {
                return nil
            }
            let end = lineStarts[token.line - 1] + token.column - 1
                + token.text.unicodeScalars.count
            guard end <= normalized.unicodeScalars.count else { return nil }
            return (end, 0, ".\(suffix)")
        }
        for function in unit.functions {
            let preceding = function.headerRange.lowerBound - 1
            guard preceding >= 0, unit.tokens[preceding].text == "const",
                  SceneAuthoredShaderValueType(authoredName: function.returnType) != nil
            else { continue }
            let token = unit.tokens[preceding]
            guard token.line > 0, token.line <= lineStarts.count else { return normalized }
            edits.append((lineStarts[token.line - 1] + token.column - 1, token.text.count, ""))
        }
        for index in scalarIntrinsicFunctionReferences(unit) {
            let token = unit.tokens[index]
            guard token.line > 0, token.line <= lineStarts.count else { return normalized }
            edits.append((lineStarts[token.line - 1] + token.column - 1, 0, "mwxAuthored_"))
        }
        return applying(edits, to: normalized)
    }

    private static func sourceLineStarts(_ source: String) -> [Int] {
        var starts = [0]
        for (index, scalar) in source.unicodeScalars.enumerated() where scalar == "\n" {
            starts.append(index + 1)
        }
        return starts
    }

    private static func applying(_ edits: [(Int, Int, String)], to source: String) -> String {
        var result = source
        for (offset, length, replacement) in edits.sorted(by: { $0.0 > $1.0 }) {
            let scalarIndex = result.unicodeScalars.index(
                result.unicodeScalars.startIndex,
                offsetBy: offset
            )
            let scalarEnd = result.unicodeScalars.index(scalarIndex, offsetBy: length)
            guard let index = String.Index(scalarIndex, within: result),
                  let end = String.Index(scalarEnd, within: result) else {
                return source
            }
            result.replaceSubrange(index..<end, with: replacement)
        }
        return result
    }

    /// GLSL rejects source-defined scalar intrinsic signatures. Preserve the
    /// author body and its references under a private name. Exact float
    /// signatures and scalar argument proofs reuse the syntax/type owners;
    /// overloads, shadowing, unknown arguments and alias collisions stay closed.
    private static func scalarIntrinsicFunctionReferences(
        _ unit: SceneAuthoredShaderSyntaxUnit
    ) -> [Int] {
        let tokens = unit.tokens
        return [("mod", 2), ("fract", 1)].flatMap { name, arity -> [Int] in
            let functions = unit.functions.filter { $0.name == name }
            guard functions.count == 1, let function = functions.first,
                  function.returnType == "float",
                  !tokens.contains(where: { $0.text == "mwxAuthored_" + name })
            else { return [] }
            let parameters = tokens[function.parameterRange].split { $0.text == "," }
            guard parameters.count == arity, parameters.allSatisfy({ parameter in
                let value = Array(parameter).filter { !["const", "in"].contains($0.text) }
                return value.count == 2 && value[0].text == "float"
                    && value[1].kind == .identifier
            }) else { return [] }
            var references: [Int] = []
            for index in tokens.indices where tokens[index].text == name {
                guard index + 1 < tokens.count, tokens[index + 1].text == "(",
                      index == 0 || tokens[index - 1].text != "." else { return [] }
                if function.headerRange.contains(index) {
                    references.append(index)
                    continue
                }
                guard let end = SceneAuthoredShaderTokenScanner.matchingParenthesis(
                    tokens: tokens, opening: index + 1
                ), let arguments = SceneAuthoredShaderBuiltInVectorConversion.argumentRanges(
                    opening: index + 1, closing: end, tokens: tokens
                ), arguments.count == arity,
                arguments.allSatisfy({ argument in
                    if name == "mod" {
                        // Preserve the existing mod admission boundary.
                        let values = Array(tokens[argument])
                        if values.count == 1 { return Double(values[0].text) != nil }
                        return values.count == 3 && values[0].kind == .identifier
                            && values[1].text == "."
                            && ["x", "y", "z", "w", "r", "g", "b", "a"].contains(values[2].text)
                    }
                    guard let expression = SceneAuthoredShaderBuiltInVectorConversion
                        .componentExpression(argument, tokens: tokens, unit: unit)
                    else { return false }
                    return [.float, .int].contains(expression.type)
                }) else { return [] }
                references.append(index)
            }
            return references
        }
    }

    /// An unambiguous user function can consume the leading components of a
    /// wider floating vector. Scalar inputs use the existing compound width
    /// proof; interface-vector inputs remain direct named values. Mutable
    /// inputs, overloaded names and unknown widths remain compiler-owned.
    static func rewrite(
        _ source: String,
        shapes: [String: Shape],
        convertsScalarArguments: Bool,
        convertsVectorArguments: Bool,
        stage: SceneShaderContract.StageKind = .fragment
    ) -> String {
        let source = convertsScalarArguments
            ? rewriteIntegerInputs(source, stage: stage) : source
        let valueType = #"(?:bool|int|uint|float|[biu]?vec[2-4]|mat[2-4])"#
        let definition = try! NSRegularExpression(
            pattern: #"\b"# + valueType
                + #"\s+([A-Za-z_]\w*)\s*\(([^()]*)\)\s*\{"#
        )
        let parameter = try! NSRegularExpression(
            pattern: #"^(?:(?:const|in|out|inout|highp|mediump|lowp)\s+)*("#
                + valueType + #")\s+[A-Za-z_]\w*$"#
        )
        let (types, conflicted) = SceneGenericShaderSourceNormalizer
            .declaredScalarVectorTypes(source, shapes: shapes)
        var signatures: [String: [[Parameter]]] = [:]
        for match in definition.matches(
            in: source,
            range: NSRange(source.startIndex..., in: source)
        ) {
            guard let nameRange = Range(match.range(at: 1), in: source),
                  let parametersRange = Range(match.range(at: 2), in: source) else {
                continue
            }
            let rawParameters = source[parametersRange]
                .split(separator: ",", omittingEmptySubsequences: false)
            if rawParameters.count == 1,
               String(rawParameters[0]).trimmingCharacters(
                   in: .whitespacesAndNewlines
               ).isEmpty {
                signatures[String(source[nameRange]), default: []].append([])
                continue
            }
            var parameters: [Parameter] = []
            for raw in rawParameters {
                let value = String(raw).trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                let range = NSRange(value.startIndex..., in: value)
                guard let parameterMatch = parameter.firstMatch(in: value, range: range),
                      parameterMatch.range == range,
                      let typeRange = Range(parameterMatch.range(at: 1), in: value) else {
                    parameters.removeAll()
                    break
                }
                let type = String(value[typeRange])
                let words = value.split(whereSeparator: { $0.isWhitespace })
                parameters.append(.init(
                    width: floatVectorWidth(type), isScalarFloat: type == "float",
                    isReadOnly: !words.contains("out") && !words.contains("inout")
                ))
            }
            guard parameters.count == rawParameters.count else { continue }
            signatures[String(source[nameRange]), default: []].append(parameters)
        }

        var replacements: [(range: NSRange, value: String)] = []
        for (name, candidates) in signatures where candidates.count == 1 {
            let parameters = candidates[0]
            guard parameters.contains(where: { $0.width != nil }) else { continue }
            let call = try! NSRegularExpression(
                pattern: #"\b"# + NSRegularExpression.escapedPattern(for: name)
                    + #"\s*\(([^()]*)\)"#
            )
            for match in call.matches(
                in: source,
                range: NSRange(source.startIndex..., in: source)
            ).reversed() {
                guard let argumentsRange = Range(match.range(at: 1), in: source) else {
                    continue
                }
                let rawArguments = source[argumentsRange]
                    .split(separator: ",", omittingEmptySubsequences: false)
                guard rawArguments.count == parameters.count else { continue }
                var arguments = rawArguments.map {
                    String($0).trimmingCharacters(in: .whitespacesAndNewlines)
                }
                var changed = false
                for index in arguments.indices {
                    if let targetWidth = parameters[index].width {
                        guard convertsVectorArguments, arguments[index].range(
                            of: #"^[A-Za-z_]\w*$"#,
                            options: .regularExpression
                        ) != nil,
                              let shape = shapes[arguments[index]],
                              shape.count == nil,
                              let sourceWidth = floatVectorWidth(shape.type),
                              sourceWidth > targetWidth,
                              !hasLocalDeclaration(arguments[index], in: source) else {
                            continue
                        }
                        arguments[index] += targetWidth == 2 ? ".xy" : ".xyz"
                        changed = true
                    } else {
                        // A scalar parameter receiving a vector-valued
                        // argument has no Vulkan GLSL overload; the backend
                        // language truncates implicitly to the first
                        // component. Producer: sine_wave_circle
                        // ApplyBlending(…, t + tint * k * mask) at the
                        // stage-link gate. Untyped arguments stay untouched —
                        // both directions fail safe (status-quo compile
                        // failure, or a `.x` on a scalar that the compiler
                        // rejects — never a silent wrong render).
                        guard convertsScalarArguments, parameters[index].isScalarFloat,
                              parameters[index].isReadOnly,
                              let width = SceneGenericShaderSourceNormalizer
                            .expressionValueWidth(
                                arguments[index],
                                types: types,
                                conflicted: conflicted
                            ), width > 1 else {
                            continue
                        }
                        arguments[index] = "(\(arguments[index])).x"
                        changed = true
                    }
                }
                guard changed else { continue }
                replacements.append(
                    (
                        range: match.range,
                        value: "\(name)(\(arguments.joined(separator: ", ")))"
                    )
                )
            }
        }
        var result = source
        for replacement in replacements.sorted(by: { $0.range.location > $1.range.location }) {
            guard let range = Range(replacement.range, in: result) else { return source }
            result.replaceSubrange(range, with: replacement.value)
        }
        return result
    }

    // An authored definition does not remove a better matching builtin
    // overload. Numeric intrinsic calls must keep backend overload resolution.
    private static let intrinsicOverloadNames: Set<String> = [
        "abs", "acos", "acosh", "all", "any", "asin", "asinh", "atan", "atan2", "atanh",
        "ceil", "clamp", "clip", "cos", "cosh", "cross", "ddx", "ddy", "degrees",
        "determinant", "dFdx", "dFdxCoarse", "dFdxFine", "dFdy", "dFdyCoarse", "dFdyFine",
        "distance", "dot", "exp", "exp2", "faceforward", "fma", "floor", "fmod", "frac",
        "fract", "frexp", "fwidth", "fwidthCoarse", "fwidthFine", "inverse", "inversesqrt",
        "isfinite", "isinf", "isnan", "ldexp", "length", "lerp", "lit", "log", "log2", "log10",
        "mad", "max", "min", "mix", "mod", "modf", "mul", "normalize", "pow", "radians",
        "rcp", "reflect", "refract", "round", "roundEven", "rsqrt", "saturate", "sign",
        "sin", "sincos", "sinh", "smoothstep", "sqrt", "step", "tan", "tanh", "transpose", "trunc",
        "floatBitsToInt", "floatBitsToUint", "intBitsToFloat", "uintBitsToFloat",
        "asint", "asuint", "asfloat", "asdouble", "noise", "noise1", "noise2", "noise3", "noise4",
        "packDouble2x32", "unpackDouble2x32", "packHalf2x16", "unpackHalf2x16",
        "packUnorm2x16", "packSnorm2x16", "packUnorm4x8", "packSnorm4x8",
        "unpackUnorm2x16", "unpackSnorm2x16", "unpackUnorm4x8", "unpackSnorm4x8",
        "lessThan", "lessThanEqual", "greaterThan", "greaterThanEqual", "equal", "notEqual", "not",
        "texture", "textureProj", "textureLod", "textureOffset", "textureProjOffset",
        "textureLodOffset", "textureProjLod", "textureProjLodOffset", "textureGrad",
        "textureGradOffset", "textureProjGrad", "textureProjGradOffset", "textureGather",
        "textureGatherOffset", "textureGatherOffsets", "textureSize", "textureQueryLod",
        "textureQueryLevels", "textureSamples", "texelFetch", "texelFetchOffset",
        "texture1D", "texture2D", "texture3D", "textureCube", "texture1DProj", "texture2DProj",
        "texture3DProj", "texture1DLod", "texture2DLod", "texture3DLod", "textureCubeLod",
        "texture1DProjLod", "texture2DProjLod", "texture3DProjLod", "texSample2D", "texSample2DLod",
        "tex1D", "tex2D", "tex3D", "texCUBE", "tex1Dbias", "tex2Dbias", "tex3Dbias", "texCUBEbias",
        "tex1Dgrad", "tex2Dgrad", "tex3Dgrad", "texCUBEgrad", "tex1Dlod", "tex2Dlod", "tex3Dlod",
        "texCUBElod", "tex1Dproj", "tex2Dproj", "tex3Dproj", "texCUBEproj",
        "imageLoad", "imageStore", "imageSize", "imageSamples",
        "uaddCarry", "usubBorrow", "umulExtended", "imulExtended", "bitfieldExtract", "bitfieldInsert",
        "bitfieldReverse", "bitCount", "findLSB", "findMSB", "f16tof32", "f32tof16",
    ]

    /// HLSL converts a floating input to an integer parameter at the call.
    /// Use the same unique root-scope proof as vector returns, never the
    /// whole-source width table: mutable/overloaded/unknown inputs stay closed.
    private static func rewriteIntegerInputs(
        _ source: String, stage: SceneShaderContract.StageKind
    ) -> String {
        let lexical = SceneAuthoredShaderLexer.lex(source: source, stage: stage)
        let analysis = SceneAuthoredShaderSyntaxAnalyzer.analyzeForTypeConversions(
            lexerOutput: lexical, stage: stage
        )
        guard analysis.diagnostics.isEmpty, let unit = analysis.unit,
              !unit.tokens.contains(where: { $0.text == "struct" }) else { return source }
        let tokens = unit.tokens
        let starts = sourceLineStarts(source)
        var edits: [(Int, Int, String)] = []
        for (name, candidates) in Dictionary(grouping: unit.functions, by: \.name)
            where candidates.count == 1 && !intrinsicOverloadNames.contains(name) {
            let function = candidates[0]
            let references = tokens.indices.filter { tokens[$0].text == name }
            // A prototype or value/member reference can hide an overload.
            guard references.allSatisfy({ index in
                index + 1 < tokens.count && tokens[index + 1].text == "("
                    && (index == 0 || tokens[index - 1].text != ".")
                    && (function.headerRange.contains(index)
                        || unit.functions.contains { $0.bodyRange.contains(index) })
            }), let parameters = SceneAuthoredShaderTokenScanner.split(
                function.parameterRange, separator: ",", tokens: tokens
            ) else { continue }
            let integerInputs = parameters.enumerated().compactMap { index, range -> Int? in
                let value = tokens[range].filter { ["const", "in"].contains($0.text) == false }
                return value.count == 2 && value[0].text == "int"
                    && value[1].kind == .identifier ? index : nil
            }
            guard !integerInputs.isEmpty else { continue }
            for call in references where !function.headerRange.contains(call) {
                guard let caller = unit.functions.first(where: { $0.bodyRange.contains(call) }),
                      let close = SceneAuthoredShaderTokenScanner.matchingParenthesis(
                        tokens: tokens, opening: call + 1
                      ), let arguments = SceneAuthoredShaderBuiltInVectorConversion.argumentRanges(
                        opening: call + 1, closing: close, tokens: tokens
                      ), arguments.count == parameters.count else { continue }
                let declarations = SceneAuthoredShaderFunctionSemantics
                    .uniqueRootScopeValueDeclarations(for: caller, in: unit)
                for index in integerInputs {
                    let argument = arguments[index]
                    guard argument.count == 1 else { continue }
                    let token = tokens[argument.lowerBound]
                    let isFloat = token.kind == .number
                        ? Double(token.text).map { $0.isFinite &&
                            (token.text.contains(".") || token.text.lowercased().contains("e")) } == true
                        : token.kind == .identifier && declarations[token.text].map {
                            $0.index < call && $0.type == "float"
                        } == true
                    guard isFloat, token.line > 0, token.line <= starts.count else { continue }
                    let offset = starts[token.line - 1] + token.column - 1
                    edits.append((offset, token.text.unicodeScalars.count, "int(\(token.text))"))
                }
            }
        }
        return applying(edits, to: source)
    }

    private static func floatVectorWidth(_ type: String) -> Int? {
        guard type.hasPrefix("vec"), let width = Int(type.dropFirst(3)),
              (2 ... 4).contains(width) else { return nil }
        return width
    }


    private static func hasLocalDeclaration(_ name: String, in source: String) -> Bool {
        let valueTypes = [
            "bool", "int", "uint", "float",
            "ivec2", "ivec3", "ivec4",
            "uvec2", "uvec3", "uvec4",
            "vec2", "vec3", "vec4", "mat2", "mat3", "mat4",
        ]
        let types = valueTypes.map(
            NSRegularExpression.escapedPattern
        ).joined(separator: "|")
        let regex = try! NSRegularExpression(
            pattern: #"\b(?:"# + types + #")\s+"#
                + NSRegularExpression.escapedPattern(for: name) + #"\b"#
        )
        return regex.firstMatch(
            in: source,
            range: NSRange(source.startIndex..., in: source)
        ) != nil
    }
}
