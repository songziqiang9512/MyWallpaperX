import Foundation

nonisolated enum SceneAuthoredShaderFrontend {
    private struct Validation {
        let uniforms: [(String, SceneAuthoredShaderValueType)]
        let textures: [SceneAuthoredShaderProgram.TextureBinding]
        let varyings: [(String, SceneAuthoredShaderValueType)]
        let diagnostics: [SceneAuthoredShaderFrontendDiagnostic]
    }

    static func compile(
        vertexSource: String,
        fragmentSource: String
    ) -> SceneAuthoredShaderFrontendOutput {
        let vertex = analyze(source: vertexSource, stage: .vertex)
        let fragment = analyze(source: fragmentSource, stage: .fragment)
        let syntaxDiagnostics = vertex.diagnostics + fragment.diagnostics
        guard let vertexUnit = vertex.unit,
              let fragmentUnit = fragment.unit,
              syntaxDiagnostics.isEmpty else {
            return .init(program: nil, diagnostics: syntaxDiagnostics)
        }
        let validation = validate(vertex: vertexUnit, fragment: fragmentUnit)
        guard validation.diagnostics.isEmpty,
              let uniformLayout = makeUniformLayout(validation.uniforms) else {
            let layoutDiagnostic = validation.diagnostics.isEmpty
                ? [SceneAuthoredShaderFrontendDiagnostic(
                    code: .invalidUniformLayout,
                    message: "Authored uniform layout could not be constructed.",
                    stage: nil,
                    line: nil,
                    column: nil
                )]
                : validation.diagnostics
            return .init(program: nil, diagnostics: layoutDiagnostic)
        }
        let emission = SceneAuthoredShaderMetalEmitter.emit(
            vertex: vertexUnit,
            fragment: fragmentUnit,
            uniforms: validation.uniforms,
            uniformLayout: uniformLayout,
            textures: validation.textures,
            varyings: validation.varyings
        )
        guard let metalSource = emission.source, emission.diagnostics.isEmpty else {
            return .init(program: nil, diagnostics: emission.diagnostics)
        }
        return .init(
            program: .init(
                metalSource: metalSource,
                vertexFunctionName: "sceneAuthoredVertex",
                fragmentFunctionName: "sceneAuthoredFragment",
                uniformLayout: uniformLayout,
                textureBindings: validation.textures,
                staticLoopWork: max(vertexUnit.staticLoopWork, fragmentUnit.staticLoopWork),
                colorTransfer: SceneAuthoredShaderColorTransferAnalyzer.analyze(fragmentUnit)
            ),
            diagnostics: []
        )
    }

    private static func analyze(
        source: String,
        stage: SceneShaderContract.StageKind
    ) -> SceneAuthoredShaderSyntaxAnalyzer.Output {
        SceneAuthoredShaderSyntaxAnalyzer.analyze(
            lexerOutput: SceneAuthoredShaderLexer.lex(source: source, stage: stage),
            stage: stage
        )
    }

    private static func validate(
        vertex: SceneAuthoredShaderSyntaxUnit,
        fragment: SceneAuthoredShaderSyntaxUnit
    ) -> Validation {
        var diagnostics: [SceneAuthoredShaderFrontendDiagnostic] = []
        let vertexAttributes = vertex.declarations.filter { $0.storage == .attribute }
        let expectedAttributes: [String: SceneAuthoredShaderValueType] = [
            "a_Position": .float3,
            "a_TexCoord": .float2,
        ]
        for declaration in vertexAttributes {
            guard declaration.arraySize == nil,
                  let type = SceneAuthoredShaderValueType(authoredName: declaration.typeName),
                  expectedAttributes[declaration.name] == type else {
                diagnostics.append(.init(
                    code: .unsupportedAttribute,
                    message: "Only vec3 a_Position and vec2 a_TexCoord attributes are supported.",
                    stage: .vertex,
                    line: declaration.line,
                    column: nil
                ))
                continue
            }
        }
        if fragment.declarations.contains(where: { $0.storage == .attribute }) {
            diagnostics.append(.init(
                code: .unsupportedAttribute,
                message: "Fragment shaders cannot declare attributes.",
                stage: .fragment,
                line: nil,
                column: nil
            ))
        }

        let vertexVaryings = typedDeclarations(vertex, storage: .varying, diagnostics: &diagnostics)
        let fragmentVaryings = typedDeclarations(fragment, storage: .varying, diagnostics: &diagnostics)
        let vertexByName = Dictionary(uniqueKeysWithValues: vertexVaryings)
        let fragmentByName = Dictionary(uniqueKeysWithValues: fragmentVaryings)
        if vertexByName != fragmentByName {
            diagnostics.append(.init(
                code: .stageLinkMismatch,
                message: "Vertex and fragment varying declarations must match exactly.",
                stage: nil,
                line: nil,
                column: nil
            ))
        }

        var uniforms: [(String, SceneAuthoredShaderValueType)] = []
        var uniformTypes: [String: SceneAuthoredShaderValueType] = [:]
        var textures: [SceneAuthoredShaderProgram.TextureBinding] = []
        var textureNames: Set<String> = []
        for unit in [vertex, fragment] {
            for declaration in unit.declarations where declaration.storage == .uniform {
                if declaration.typeName == "sampler2D" {
                    guard declaration.arraySize == nil,
                          let slot = textureSlot(declaration.name) else {
                        diagnostics.append(.init(
                            code: .unsupportedSampler,
                            message: "Only g_Texture0 through g_Texture7 sampler2D uniforms are supported.",
                            stage: unit.stage,
                            line: declaration.line,
                            column: nil
                        ))
                        continue
                    }
                    if textureNames.insert(declaration.name).inserted {
                        textures.append(.init(name: declaration.name, slot: slot))
                    }
                    continue
                }
                guard declaration.arraySize == nil,
                      let type = SceneAuthoredShaderValueType(authoredName: declaration.typeName),
                      type != .bool else {
                    diagnostics.append(.init(
                        code: .unsupportedType,
                        message: "Uniform '\(declaration.name)' has an unsupported type or array shape.",
                        stage: unit.stage,
                        line: declaration.line,
                        column: nil
                    ))
                    continue
                }
                if let existing = uniformTypes[declaration.name], existing != type {
                    diagnostics.append(.init(
                        code: .duplicateDeclaration,
                        message: "Uniform '\(declaration.name)' has conflicting stage types.",
                        stage: unit.stage,
                        line: declaration.line,
                        column: nil
                    ))
                } else if uniformTypes.updateValue(type, forKey: declaration.name) == nil {
                    uniforms.append((declaration.name, type))
                }
            }
        }
        textures.sort { $0.slot < $1.slot }
        return Validation(
            uniforms: uniforms,
            textures: textures,
            varyings: vertexVaryings,
            diagnostics: diagnostics
        )
    }

    private static func typedDeclarations(
        _ unit: SceneAuthoredShaderSyntaxUnit,
        storage: SceneAuthoredShaderSyntaxUnit.Storage,
        diagnostics: inout [SceneAuthoredShaderFrontendDiagnostic]
    ) -> [(String, SceneAuthoredShaderValueType)] {
        unit.declarations.compactMap { declaration in
            guard declaration.storage == storage else { return nil }
            guard declaration.arraySize == nil,
                  let type = SceneAuthoredShaderValueType(authoredName: declaration.typeName) else {
                diagnostics.append(.init(
                    code: .unsupportedType,
                    message: "Stage declaration '\(declaration.name)' has an unsupported type or array shape.",
                    stage: unit.stage,
                    line: declaration.line,
                    column: nil
                ))
                return nil
            }
            return (declaration.name, type)
        }
    }

    private static func textureSlot(_ name: String) -> Int? {
        guard name.hasPrefix("g_Texture"),
              let slot = Int(name.dropFirst("g_Texture".count)),
              (0 ... 7).contains(slot) else {
            return nil
        }
        return slot
    }

    private static func makeUniformLayout(
        _ uniforms: [(String, SceneAuthoredShaderValueType)]
    ) -> SceneAuthoredShaderUniformLayout? {
        var fields: [SceneAuthoredShaderUniformLayout.Field] = []
        var offset = 0
        for (name, type) in uniforms + [("mwxRenderSize", .float2)] {
            let remainder = offset % type.alignment
            if remainder != 0 { offset += type.alignment - remainder }
            fields.append(.init(name: name, type: type, offset: offset))
            let (next, overflow) = offset.addingReportingOverflow(type.byteSize)
            guard !overflow else { return nil }
            offset = next
        }
        let remainder = offset % 16
        if remainder != 0 { offset += 16 - remainder }
        guard offset <= 4_096 else { return nil }
        return .init(fields: fields, byteSize: offset)
    }
}

/// Derives a deliberately small color transfer fact from the same active
/// syntax unit that the authored frontend emits. It does not inspect paths,
/// effect identities, render state, or shader fingerprints.
nonisolated enum SceneAuthoredShaderColorTransferAnalyzer {
    static func analyze(
        _ fragment: SceneAuthoredShaderSyntaxUnit
    ) -> SceneShaderColorTransfer {
        guard fragment.stage == .fragment,
              let main = fragment.functions.first(where: { $0.name == "main" }) else {
            return .unresolved
        }
        let tokens = fragment.tokens
        let outputUses = tokens.indices.filter { tokens[$0].text == "gl_FragColor" }
        guard outputUses.count == 1,
              let assignment = outputUses.first,
              assignment + 1 < tokens.count,
              tokens[assignment + 1].text == "=",
              main.bodyRange.contains(assignment),
              isUnconditionalWrite(assignment, tokens: tokens, body: main.bodyRange),
              let expression = assignmentExpression(
                  after: assignment,
                  in: tokens,
                  body: main.bodyRange
              ) else {
            return .unresolved
        }
        if let slot = directTextureSampleSlot(expression) {
            return .passthrough(textureSlot: slot)
        }
        return isOpaqueVectorConstruction(expression) ? .opaque : .unresolved
    }

    private static func isUnconditionalWrite(
        _ assignment: Int,
        tokens: [SceneAuthoredShaderToken],
        body: Range<Int>
    ) -> Bool {
        let controlFlow: Set<String> = [
            "if", "else", "for", "while", "do", "switch", "case", "discard", "return",
        ]
        guard !body.contains(where: {
            tokens[$0].kind == .identifier && controlFlow.contains(tokens[$0].text)
        }) else {
            return false
        }
        var braceDepth = 0
        for index in body.lowerBound...assignment {
            if tokens[index].text == "{" { braceDepth += 1 }
            if tokens[index].text == "}" { braceDepth -= 1 }
        }
        return braceDepth == 1
    }

    private static func assignmentExpression(
        after assignment: Int,
        in tokens: [SceneAuthoredShaderToken],
        body: Range<Int>
    ) -> ArraySlice<SceneAuthoredShaderToken>? {
        let start = assignment + 2
        guard body.contains(start) else { return nil }
        var stack: [String] = []
        let closing: [String: String] = [")": "(", "]": "[", "}": "{"]
        for index in start..<body.upperBound {
            let text = tokens[index].text
            if ["(", "[", "{"].contains(text) {
                stack.append(text)
            } else if let expected = closing[text] {
                guard stack.last == expected else { return nil }
                stack.removeLast()
            } else if text == ";", stack.isEmpty {
                guard index > start else { return nil }
                return tokens[start..<index]
            }
        }
        return nil
    }

    private static func directTextureSampleSlot(
        _ expression: ArraySlice<SceneAuthoredShaderToken>
    ) -> Int? {
        let tokens = Array(expression)
        guard tokens.count >= 6,
              ["texSample2D", "texture2D"].contains(tokens[0].text),
              tokens[1].text == "(",
              tokens.last?.text == ")",
              outerCallClosesAtEnd(tokens),
              topLevelCommas(tokens) == [3],
              let slot = textureSlot(tokens[2].text) else {
            return nil
        }
        return slot
    }

    private static func isOpaqueVectorConstruction(
        _ expression: ArraySlice<SceneAuthoredShaderToken>
    ) -> Bool {
        let tokens = Array(expression)
        guard tokens.count >= 6,
              ["vec4", "float4"].contains(tokens[0].text),
              tokens[1].text == "(",
              tokens.last?.text == ")",
              outerCallClosesAtEnd(tokens),
              let comma = topLevelCommas(tokens).last,
              comma + 2 == tokens.count - 1,
              tokens[comma + 1].kind == .number,
              Double(tokens[comma + 1].text) == 1 else {
            return false
        }
        return true
    }

    private static func outerCallClosesAtEnd(
        _ tokens: [SceneAuthoredShaderToken]
    ) -> Bool {
        var depth = 0
        for index in 1..<tokens.count {
            if tokens[index].text == "(" { depth += 1 }
            if tokens[index].text == ")" {
                depth -= 1
                if depth == 0 { return index == tokens.count - 1 }
                if depth < 0 { return false }
            }
        }
        return false
    }

    private static func topLevelCommas(
        _ tokens: [SceneAuthoredShaderToken]
    ) -> [Int] {
        var depth = 0
        var result: [Int] = []
        for index in tokens.indices {
            if tokens[index].text == "(" { depth += 1 }
            if tokens[index].text == ")" { depth -= 1 }
            if tokens[index].text == ",", depth == 1 { result.append(index) }
        }
        return result
    }

    private static func textureSlot(_ name: String) -> Int? {
        guard name.hasPrefix("g_Texture"),
              let slot = Int(name.dropFirst("g_Texture".count)),
              (0...7).contains(slot) else {
            return nil
        }
        return slot
    }
}
