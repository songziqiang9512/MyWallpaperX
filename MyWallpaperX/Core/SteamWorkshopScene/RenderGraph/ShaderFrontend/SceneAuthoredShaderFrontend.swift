import Foundation

nonisolated enum SceneAuthoredShaderFrontend {
    private struct Validation {
        let uniforms: [SceneAuthoredShaderUniformDeclaration]
        let textures: [SceneAuthoredShaderProgram.TextureBinding]
        let varyings: [(String, SceneAuthoredShaderValueType, Int?)]
        let varyingPrefixFacts: [String: SceneAuthoredShaderVaryingPrefixLink.Fact]
        let omittedVertexStatementRanges: [Range<Int>]
        let diagnostics: [SceneAuthoredShaderFrontendDiagnostic]
    }

    static func compile(
        vertexSource: String,
        fragmentSource: String,
        runtimeLoopBounds: SceneAuthoredShaderRuntimeLoopBounds = .none
    ) -> SceneAuthoredShaderFrontendOutput {
        let vertex = analyze(
            source: vertexSource,
            stage: .vertex,
            provenRuntimeLoopBounds: runtimeLoopBounds.vertex
        )
        let fragment = analyze(
            source: fragmentSource,
            stage: .fragment,
            provenRuntimeLoopBounds: runtimeLoopBounds.fragment
        )
        let syntaxDiagnostics = vertex.diagnostics + fragment.diagnostics
        guard let vertexUnit = vertex.unit,
              let fragmentUnit = fragment.unit,
              syntaxDiagnostics.isEmpty else {
            return .init(program: nil, diagnostics: syntaxDiagnostics)
        }
        let validation = validate(vertex: vertexUnit, fragment: fragmentUnit)
        guard validation.diagnostics.isEmpty,
              let uniformLayout = makeUniformLayout(
                  validation.uniforms,
                  textures: validation.textures
              ) else {
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
        let fragmentOutputChannelUse = SceneAuthoredShaderFragmentOutputAnalyzer
            .analyze(fragmentUnit)
        let emission = SceneAuthoredShaderMetalEmitter.emit(
            vertex: vertexUnit,
            fragment: fragmentUnit,
            uniforms: validation.uniforms,
            uniformLayout: uniformLayout,
            textures: validation.textures,
            varyings: validation.varyings,
            varyingPrefixFacts: validation.varyingPrefixFacts,
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
                colorTransfer: colorTransfer,
                fragmentOutputChannelUse: fragmentOutputChannelUse
            ),
            diagnostics: []
        )
    }

    private static func analyze(
        source: String,
        stage: SceneShaderContract.StageKind,
        provenRuntimeLoopBounds: [String: SceneAuthoredShaderExactScalarFact]
    ) -> SceneAuthoredShaderSyntaxAnalyzer.Output {
        SceneAuthoredShaderSyntaxAnalyzer.analyze(
            lexerOutput: SceneAuthoredShaderLexer.lex(source: source, stage: stage),
            stage: stage,
            provenRuntimeLoopBounds: provenRuntimeLoopBounds
        )
    }

    private static func validate(
        vertex: SceneAuthoredShaderSyntaxUnit,
        fragment: SceneAuthoredShaderSyntaxUnit
    ) -> Validation {
        var diagnostics: [SceneAuthoredShaderFrontendDiagnostic] = []
        diagnostics += SceneAuthoredShaderFunctionSemantics.diagnostics(for: vertex)
        diagnostics += SceneAuthoredShaderFunctionSemantics.diagnostics(for: fragment)
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
            SceneAuthoredShaderGlobalReferenceAnalyzer.isReferenced(
                $0.0,
                in: fragment
            )
        }
        var varyingPrefixFacts: [String: SceneAuthoredShaderVaryingPrefixLink.Fact] = [:]
        let hasLinkMismatch = activeFragmentVaryings.contains { fragmentVarying in
            guard let vertexVarying = vertexByName[fragmentVarying.0] else { return true }
            if vertexVarying.0 == fragmentVarying.1,
               vertexVarying.1 == fragmentVarying.2 { return false }
            guard vertexVarying.1 == nil, fragmentVarying.2 == nil,
                  let vertexWidth = floatVectorWidth(vertexVarying.0),
                  let fragmentWidth = floatVectorWidth(fragmentVarying.1),
                  let fact = SceneAuthoredShaderVaryingPrefixLink.prove(
                      name: fragmentVarying.0,
                      vertexWidth: vertexWidth,
                      fragmentWidth: fragmentWidth,
                      vertex: vertex,
                      fragment: fragment
                  ) else { return true }
            varyingPrefixFacts[fragmentVarying.0] = fact
            return false
        }
        if hasLinkMismatch {
            diagnostics.append(.init(
                code: .stageLinkMismatch,
                message: "Every consumed fragment varying requires a matching vertex output.",
                stage: nil,
                line: nil,
                column: nil
            ))
        }

        var uniforms: [SceneAuthoredShaderUniformDeclaration] = []
        var seenUniforms: Set<String> = []
        var textures: [SceneAuthoredShaderProgram.TextureBinding] = []
        var textureNames: Set<String> = []
        let uniformStages = Dictionary(grouping: [vertex, fragment].flatMap { unit in
            unit.declarations.compactMap { declaration in
                declaration.storage == .uniform && declaration.typeName != "sampler2D"
                    ? (declaration.name, unit.stage) : nil
            }
        }, by: \.0).mapValues { Set($0.map(\.1)) }
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
                        textures.append(.init(
                            name: declaration.name,
                            slot: slot,
                            channelUse: SceneAuthoredShaderTextureChannelAnalyzer.analyze(
                                samplerName: declaration.name,
                                vertex: vertex,
                                fragment: fragment
                            )
                        ))
                    }
                    continue
                }
                if declaration.name == "mwxRenderSize"
                    || SceneMaterialTextureTransformABI.component(
                        forFieldName: declaration.name
                    ) != nil {
                    diagnostics.append(.init(
                        code: .unsupportedDeclaration,
                        message: "Uniform '\(declaration.name)' is reserved by the host ABI.",
                        stage: unit.stage,
                        line: declaration.line,
                        column: nil
                    ))
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
                ) || (type == .float
                    && unit.exactRuntimeLoopUniformArrays.contains(declaration.name)) else {
                    diagnostics.append(.init(
                        code: .unsupportedType,
                        message: "Uniform '\(declaration.name)' has an unsupported array shape.",
                        stage: unit.stage,
                        line: declaration.line,
                        column: nil
                    ))
                    continue
                }
                let identity = "\(unit.stage.rawValue):\(declaration.name)"
                if seenUniforms.insert(identity).inserted,
                   !deadBindings.omittedUniformNames.contains(declaration.name),
                   SceneAuthoredShaderGlobalReferenceAnalyzer.isReferenced(
                       declaration.name,
                       in: unit
                   ) {
                    let fieldName = uniformStages[declaration.name]?.count == 1
                        ? declaration.name
                        : "mwx\(unit.stage == .vertex ? "V" : "F")_\(declaration.name)"
                    uniforms.append(.init(
                        authoredName: declaration.name,
                        fieldName: fieldName,
                        type: type,
                        arrayCount: arrayCount,
                        stage: unit.stage
                    ))
                }
            }
        }
        textures.sort { $0.slot < $1.slot }
        return Validation(
            uniforms: uniforms,
            textures: textures,
            varyings: vertexVaryings,
            varyingPrefixFacts: varyingPrefixFacts,
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

    private static func floatVectorWidth(
        _ type: SceneAuthoredShaderValueType
    ) -> Int? {
        switch type {
        case .float2: 2
        case .float3: 3
        case .float4: 4
        default: nil
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
        _ uniforms: [SceneAuthoredShaderUniformDeclaration],
        textures: [SceneAuthoredShaderProgram.TextureBinding]
    ) -> SceneAuthoredShaderUniformLayout? {
        var fields: [SceneAuthoredShaderUniformLayout.Field] = []
        var offset = 0
        for uniform in uniforms {
            let (type, arrayCount) = (uniform.type, uniform.arrayCount)
            let remainder = offset % type.alignment
            if remainder != 0 { offset += type.alignment - remainder }
            fields.append(.init(
                name: uniform.fieldName,
                authoredName: uniform.authoredName,
                stage: uniform.stage,
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
        let internalType = SceneAuthoredShaderValueType.float2
        let internalRemainder = offset % internalType.alignment
        if internalRemainder != 0 { offset += internalType.alignment - internalRemainder }
        fields.append(.init(name: "mwxRenderSize", type: internalType, offset: offset))
        offset += internalType.byteSize
        guard let transforms = SceneMaterialTextureTransformABI.fields(
            activeSlots: textures.map(\.slot),
            startingAt: offset
        ) else { return nil }
        fields += transforms.fields
        offset = transforms.endOffset
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
