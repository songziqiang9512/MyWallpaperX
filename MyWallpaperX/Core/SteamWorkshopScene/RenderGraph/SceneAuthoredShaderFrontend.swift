import Foundation

nonisolated enum SceneAuthoredShaderFrontend {
    private struct Validation {
        let uniforms: [(String, SceneAuthoredShaderValueType, Int?)]
        let textures: [SceneAuthoredShaderProgram.TextureBinding]
        let varyings: [(String, SceneAuthoredShaderValueType, Int?)]
        let omittedVertexStatementRanges: [Range<Int>]
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
        let colorTransfer = SceneAuthoredShaderColorTransferAnalyzer.analyze(fragmentUnit)
        let emission = SceneAuthoredShaderMetalEmitter.emit(
            vertex: vertexUnit,
            fragment: fragmentUnit,
            uniforms: validation.uniforms,
            uniformLayout: uniformLayout,
            textures: validation.textures,
            varyings: validation.varyings,
            omittedVertexStatementRanges: validation.omittedVertexStatementRanges,
            colorTransfer: colorTransfer
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
                colorTransfer: colorTransfer
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
        let deadBindings = SceneAuthoredShaderDeadBindingAnalyzer.analyze(
            vertex: vertex,
            fragment: fragment
        )
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
        if vertexVaryings.reduce(0, { $0 + ($1.2 ?? 1) }) > 32 {
            diagnostics.append(.init(
                code: .unsupportedType,
                message: "Vertex varyings exceed the 32-location frontend limit.",
                stage: .vertex,
                line: nil,
                column: nil
            ))
        }
        let vertexByName = Dictionary(uniqueKeysWithValues: vertexVaryings.map {
            ($0.0, ($0.1, $0.2))
        })
        let activeFragmentVaryings = fragmentVaryings.filter {
            declarationIsReferenced($0.0, in: fragment)
        }
        if activeFragmentVaryings.contains(where: {
            guard let vertex = vertexByName[$0.0] else { return true }
            return vertex.0 != $0.1 || vertex.1 != $0.2
        }) {
            diagnostics.append(.init(
                code: .stageLinkMismatch,
                message: "Every consumed fragment varying requires a matching vertex output.",
                stage: nil,
                line: nil,
                column: nil
            ))
        }

        var uniforms: [(String, SceneAuthoredShaderValueType, Int?)] = []
        var uniformTypes: [String: SceneAuthoredShaderValueType] = [:]
        var uniformArrayCounts: [String: Int?] = [:]
        var textures: [SceneAuthoredShaderProgram.TextureBinding] = []
        var textureNames: Set<String> = []
        let referencedUniformNames = Set([vertex, fragment].flatMap { unit in
            unit.declarations.compactMap { declaration -> String? in
                guard declaration.storage == .uniform,
                      declaration.typeName != "sampler2D",
                      declarationIsReferenced(declaration.name, in: unit) else {
                    return nil
                }
                return declaration.name
            }
        })
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
                    if deadBindings.activeSamplerNames.contains(declaration.name),
                       textureNames.insert(declaration.name).inserted {
                        textures.append(.init(name: declaration.name, slot: slot))
                    }
                    continue
                }
                guard let type = SceneAuthoredShaderValueType(
                    authoredName: declaration.typeName
                ), type != .bool else {
                    diagnostics.append(.init(
                        code: .unsupportedType,
                        message: "Uniform '\(declaration.name)' has an unsupported type or array shape.",
                        stage: unit.stage,
                        line: declaration.line,
                        column: nil
                    ))
                    continue
                }
                let arrayCount = declaration.arraySize
                guard arrayCount == nil || isAudioSpectrumArray(
                    name: declaration.name,
                    type: type,
                    count: arrayCount
                ) else {
                    diagnostics.append(.init(
                        code: .unsupportedType,
                        message: "Uniform '\(declaration.name)' has an unsupported array shape.",
                        stage: unit.stage,
                        line: declaration.line,
                        column: nil
                    ))
                    continue
                }
                if let existing = uniformTypes[declaration.name] {
                    if existing != type || uniformArrayCounts[declaration.name] != arrayCount {
                        diagnostics.append(.init(
                            code: .duplicateDeclaration,
                            message: existing == type
                                ? "Uniform '\(declaration.name)' has conflicting array shapes."
                                : "Uniform '\(declaration.name)' has conflicting stage types.",
                            stage: unit.stage,
                            line: declaration.line,
                            column: nil
                        ))
                    }
                } else {
                    uniformTypes[declaration.name] = type
                    uniformArrayCounts[declaration.name] = arrayCount
                    if !deadBindings.omittedUniformNames.contains(declaration.name),
                       referencedUniformNames.contains(declaration.name)
                           || !isTextureResolutionUniformName(declaration.name) {
                        uniforms.append((declaration.name, type, arrayCount))
                    }
                }
            }
        }
        textures.sort { $0.slot < $1.slot }
        return Validation(
            uniforms: uniforms,
            textures: textures,
            varyings: vertexVaryings,
            omittedVertexStatementRanges: deadBindings.omittedVertexStatementRanges,
            diagnostics: diagnostics
        )
    }

    private static func typedDeclarations(
        _ unit: SceneAuthoredShaderSyntaxUnit,
        storage: SceneAuthoredShaderSyntaxUnit.Storage,
        diagnostics: inout [SceneAuthoredShaderFrontendDiagnostic]
    ) -> [(String, SceneAuthoredShaderValueType, Int?)] {
        unit.declarations.compactMap { declaration in
            guard declaration.storage == storage else { return nil }
            guard let type = SceneAuthoredShaderValueType(authoredName: declaration.typeName),
                  supportedVaryingArray(type: type, count: declaration.arraySize) else {
                diagnostics.append(.init(
                    code: .unsupportedType,
                    message: "Stage declaration '\(declaration.name)' has an unsupported type or array shape.",
                    stage: unit.stage,
                    line: declaration.line,
                    column: nil
                ))
                return nil
            }
            return (declaration.name, type, declaration.arraySize)
        }
    }

    private static func supportedVaryingArray(
        type: SceneAuthoredShaderValueType,
        count: Int?
    ) -> Bool {
        guard let count else { return true }
        return (1 ... 16).contains(count)
            && [.float, .float2, .float3, .float4].contains(type)
    }

    private static func declarationIsReferenced(
        _ name: String,
        in unit: SceneAuthoredShaderSyntaxUnit
    ) -> Bool {
        let declarationRanges = unit.declarations.filter {
            $0.name == name
        }.map(\.range)
        return unit.tokens.indices.contains { index in
            unit.tokens[index].text == name
                && !declarationRanges.contains(where: { $0.contains(index) })
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

    private static func isTextureResolutionUniformName(_ name: String) -> Bool {
        guard name.hasPrefix("g_Texture"), name.hasSuffix("Resolution") else {
            return false
        }
        let start = name.index(name.startIndex, offsetBy: "g_Texture".count)
        let end = name.index(name.endIndex, offsetBy: -"Resolution".count)
        return start < end
            && Int(name[start ..< end]).map { (0 ... 7).contains($0) } == true
    }

    private static func makeUniformLayout(
        _ uniforms: [(String, SceneAuthoredShaderValueType, Int?)]
    ) -> SceneAuthoredShaderUniformLayout? {
        var fields: [SceneAuthoredShaderUniformLayout.Field] = []
        var offset = 0
        for (name, type, arrayCount) in uniforms
            + [("mwxRenderSize", .float2, nil)] {
            let remainder = offset % type.alignment
            if remainder != 0 { offset += type.alignment - remainder }
            fields.append(.init(
                name: name,
                type: type,
                arrayCount: arrayCount,
                offset: offset
            ))
            let (next, overflow) = offset.addingReportingOverflow(
                type.byteSize * (arrayCount ?? 1)
            )
            guard !overflow else { return nil }
            offset = next
        }
        let remainder = offset % 16
        if remainder != 0 { offset += 16 - remainder }
        guard offset <= 4_096 else { return nil }
        return .init(fields: fields, byteSize: offset)
    }

    private static func isAudioSpectrumArray(
        name: String,
        type: SceneAuthoredShaderValueType,
        count: Int?
    ) -> Bool {
        guard type == .float,
              let count,
              [16, 32, 64].contains(count) else { return false }
        return ["Left", "Right"].contains { channel in
            name == "g_AudioSpectrum\(count)\(channel)"
        }
    }
}
