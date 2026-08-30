import Foundation

/// Lowers reflected glslang/SPIRV-Cross output into the product Program
/// artifact. It accepts only the bounded ABI, loop, texture, and color forms
/// that the compositor can state precisely; all other output fails closed.
nonisolated enum SceneGenericShaderArtifactBuilder {
    struct Stage {
        let name: String
        /// Exact normalized source compiled by glslang. This owns compiler
        /// budgets, never authored material semantics.
        let source: String
        /// Prepared authored source before backend normalization. Shared
        /// material analyzers use this identity to derive semantic facts.
        let authoredSource: String
        let msl: String
        let reflection: Data
    }

    enum Failure: Error, Equatable {
        case reflection
        case uniformBlock
        case uniformStageMismatch
        case uniformMember
        case texture
        case textureUnused
        case uniformStruct
        case stageHelperConflict
        case loopUnbounded
        case loopBudget
        case colorTransfer
        case metalSize
    }

    private struct Reflection: Decodable {
        struct UniformBlock: Decodable {
            let type: String
            let blockSize: Int
            let set: Int
            let binding: Int

            enum CodingKeys: String, CodingKey {
                case type, set, binding
                case blockSize = "block_size"
            }
        }

        struct ReflectedType: Decodable {
            struct Member: Decodable {
                let name: String
                let type: String
                let offset: Int?
                let array: [Int]?
            }
            let members: [Member]
        }

        struct Texture: Decodable {
            let name: String
            let binding: Int
        }

        let types: [String: ReflectedType]
        let ubos: [UniformBlock]
        let textures: [Texture]?
    }

    struct ReflectedLayout: Equatable {
        let fields: [SceneGenericShaderProgramArtifact.Program.UniformLayout.Field]
        let byteSize: Int
    }

    static func build(
        requestKey: String,
        backendID: String,
        outputSemantics: SceneGenericShaderOutputSemantics = .color,
        premultipliedColorInputSlots: Set<Int> = [],
        stages: [Stage],
        maximumArtifactBytes: Int
    ) -> Result<SceneGenericShaderProgramArtifact, Failure> {
        guard stages.map(\.name).sorted() == ["fragment", "vertex"] else {
            return .failure(.reflection)
        }
        do {
            var decoded: [String: Reflection] = [:]
            for stage in stages {
                decoded[stage.name] = try JSONDecoder().decode(
                    Reflection.self,
                    from: stage.reflection
                )
            }
            guard let vertexStage = stages.first(where: { $0.name == "vertex" }),
                  let fragmentStage = stages.first(where: { $0.name == "fragment" }),
                  let vertexReflection = decoded["vertex"],
                  let fragmentReflection = decoded["fragment"] else {
                throw Failure.reflection
            }
            let vertexLayout = try reflectedLayout(vertexReflection)
            let fragmentLayout = try reflectedLayout(fragmentReflection)
            let stagedUniforms = try stageLocalUniformLayout(
                vertex: try activeUniformFields(
                    vertexLayout.fields,
                    in: vertexStage.msl
                ),
                fragment: try activeUniformFields(
                    fragmentLayout.fields,
                    in: fragmentStage.msl
                )
            )
            let resolutionTextureSlots = resolutionTextureDependencySlots(
                layout: stagedUniforms.layout,
                authoredSources: stages.map(\.authoredSource)
            )
            guard let uniformLayout = addingTextureTransformFields(
                to: stagedUniforms.layout,
                activeSlots: resolutionTextureSlots
            ) else {
                throw Failure.uniformStageMismatch
            }
            var outputChannelUse = SceneAuthoredShaderFragmentOutputAnalyzer.analyze(
                source: fragmentStage.source
            )
            let color: (
                msl: String,
                transfer: SceneGenericShaderProgramArtifact.Program.ColorTransfer
            )
            switch outputSemantics {
            case .color:
                color = try prepareColorTransfer(
                    msl: fragmentStage.msl,
                    authoredSource: fragmentStage.authoredSource
                )
            case .redGreenUnorm:
                guard SceneAuthoredShaderColorTransferAnalyzer.isScalarSplatOutput(
                    fragmentSource: fragmentStage.authoredSource
                ) else {
                    throw Failure.colorTransfer
                }
                outputChannelUse = .redDefined
                color = (
                    fragmentStage.msl,
                    .init(kind: "red-green-unorm-data", slot: nil, slots: nil)
                )
            case .preservedRGBAUnorm:
                outputChannelUse = SceneAuthoredShaderFragmentOutputAnalyzer.analyze(
                    source: fragmentStage.authoredSource
                )
                guard outputChannelUse == .redDefined else {
                    throw Failure.colorTransfer
                }
                color = (
                    fragmentStage.msl,
                    .init(kind: "preserved-rgba-data", slot: nil, slots: nil)
                )
            }
            let preparedColorMSL: String
            if premultipliedColorInputSlots.isEmpty {
                preparedColorMSL = color.msl
            } else if let lowered = lowerPremultipliedColorInputs(
                color.msl,
                slots: premultipliedColorInputSlots
            ) {
                preparedColorMSL = lowered
            } else {
                throw Failure.colorTransfer
            }
            var vertexMSL = try normalizeUniformStruct(
                vertexStage.msl,
                layout: uniformLayout,
                fieldNames: stagedUniforms.vertexNames
            )
            var fragmentMSL = try normalizeUniformStruct(
                preparedColorMSL,
                layout: uniformLayout,
                fieldNames: stagedUniforms.fragmentNames
            )
            vertexMSL = vertexMSL.replacingOccurrences(
                of: "MWXUniforms", with: "MWXVertexUniforms"
            )
            fragmentMSL = fragmentMSL.replacingOccurrences(
                of: "MWXUniforms", with: "MWXFragmentUniforms"
            )
            (vertexMSL, fragmentMSL) = try deduplicateStageHelper(
                vertex: vertexMSL,
                fragment: fragmentMSL
            )
            let metalSource = vertexMSL.trimmingCharacters(in: .whitespacesAndNewlines)
                + "\n\n" + fragmentMSL.trimmingCharacters(in: .whitespacesAndNewlines)
                + "\n"
            guard metalSource.utf8.count <= maximumArtifactBytes else {
                throw Failure.metalSize
            }
            let bindings = try textureBindings(
                reflections: [vertexReflection, fragmentReflection],
                metalSource: metalSource,
                resolutionTextureSlots: resolutionTextureSlots
            )
            guard validTextureTransformLayout(
                uniformLayout,
                activeSlots: Set(bindings.map(\.slot))
            ) else {
                throw Failure.uniformStageMismatch
            }
            guard colorTransfer(color.transfer, isBoundBy: bindings) else {
                throw Failure.colorTransfer
            }
            guard premultipliedColorInputSlots.isSubset(
                of: Set(bindings.map(\.slot))
            ) else { throw Failure.colorTransfer }
            let accumulatorLoopWork = color.transfer.kind
                    == "independent-alpha-signal-preserving"
                ? SceneAuthoredShaderIndependentSignalAccumulatorAnalyzer
                    .staticLoopWork(fragmentSource: fragmentStage.authoredSource)
                : nil
            let genericLoopSources = accumulatorLoopWork == nil
                ? stages.map(\.source)
                : [vertexStage.source]
            let loopWork: Int
            switch SceneGenericShaderBoundedLoopWork.evaluate(
                sources: genericLoopSources
            ) {
            case let .success(work):
                loopWork = work + (accumulatorLoopWork ?? 0)
                guard loopWork <= 256 else { throw Failure.loopBudget }
            case .failure(.unbounded):
                throw Failure.loopUnbounded
            case .failure(.budget):
                throw Failure.loopBudget
            }
            let program = SceneGenericShaderProgramArtifact.Program(
                metalSource: metalSource,
                metalSourceSHA256: SceneGenericShaderProgramArtifact.sha256(
                    Data(metalSource.utf8)
                ),
                vertexFunctionName: "mwxGenericVertex",
                fragmentFunctionName: "mwxGenericFragment",
                uniformBufferIndex: 8,
                uniformLayout: .init(
                    fields: uniformLayout.fields,
                    byteSize: uniformLayout.byteSize
                ),
                textureBindings: bindings,
                staticLoopWork: loopWork,
                premultipliedColorInputSlots:
                    premultipliedColorInputSlots.sorted(),
                colorTransfer: color.transfer,
                fragmentOutputChannelUse: outputChannelUse.rawValue
            )
            return .success(.init(
                backendID: backendID,
                requestKey: requestKey,
                outputSemantics: outputSemantics,
                program: program
            ))
        } catch let failure as Failure {
            return .failure(failure)
        } catch {
            return .failure(.reflection)
        }
    }

    private static func reflectedLayout(_ reflection: Reflection) throws -> ReflectedLayout {
        guard reflection.ubos.count == 1,
              let block = reflection.ubos.first,
              block.set == 0, block.binding == 8,
              (0 ... 4_096).contains(block.blockSize),
              let type = reflection.types[block.type] else {
            throw Failure.uniformBlock
        }
        let fields = try type.members.map { member ->
            SceneGenericShaderProgramArtifact.Program.UniformLayout.Field in
            guard let valueType = SceneAuthoredShaderValueType(authoredName: member.type),
                  let offset = member.offset, offset >= 0 else {
                throw Failure.uniformMember
            }
            let arrayCount = try reflectedArrayCount(
                member.array,
                name: member.name,
                type: valueType
            )
            return .init(
                name: member.name,
                authoredName: member.name,
                type: valueType.rawValue,
                offset: offset,
                arrayCount: arrayCount
            )
        }
        return .init(fields: fields, byteSize: align(block.blockSize, to: 16))
    }

    private static func reflectedArrayCount(
        _ dimensions: [Int]?,
        name: String,
        type: SceneAuthoredShaderValueType
    ) throws -> Int? {
        guard let dimensions else { return nil }
        guard dimensions.count == 1, let count = dimensions.first,
              type == .float, [16, 32, 64].contains(count),
              name == "g_AudioSpectrum\(count)Left"
                || name == "g_AudioSpectrum\(count)Right" else {
            throw Failure.uniformMember
        }
        return count
    }

    private static func textureBindings(
        reflections: [Reflection],
        metalSource: String,
        resolutionTextureSlots: Set<Int>
    ) throws -> [SceneGenericShaderProgramArtifact.Program.TextureBinding] {
        var names: [Int: String] = [:]
        for reflection in reflections {
            for texture in reflection.textures ?? [] {
                guard (0 ..< 8).contains(texture.binding),
                      texture.name == "g_Texture\(texture.binding)",
                      names[texture.binding].map({ $0 == texture.name }) ?? true else {
                    throw Failure.texture
                }
                names[texture.binding] = texture.name
            }
        }
        for slot in resolutionTextureSlots {
            names[slot] = "g_Texture\(slot)"
        }
        return try names.sorted(by: { $0.key < $1.key }).map { slot, name in
            let sampled = regexMatches(
                #"\b"# + escaped(name) + #"\.sample\s*\("#,
                metalSource
            )
            guard sampled || resolutionTextureSlots.contains(slot) else {
                throw Failure.textureUnused
            }
            let use = sampled ? try channelUse(of: name, in: metalSource) : "unproven"
            return .init(name: name, slot: slot, channelUse: use)
        }
    }

    private static func channelUse(of name: String, in source: String) throws -> String {
        let marker = regex(#"\b"# + escaped(name) + #"\.sample\s*\("#)
        let matches = marker.matches(in: source, range: fullRange(source))
        guard !matches.isEmpty else { throw Failure.textureUnused }
        var componentMask = 0
        var observesWholeVector = false
        for match in matches {
            guard let range = Range(match.range, in: source),
                  let opening = source[range].lastIndex(of: "("),
                  let end = closingParenthesis(in: source, from: opening) else {
                return "unproven"
            }
            let suffix = source[end...]
            let currentMask: Int
            if suffix.range(of: #"^\s*\.x\b"#, options: .regularExpression) != nil {
                currentMask = 1
            } else if suffix.range(of: #"^\s*\.y\b"#, options: .regularExpression) != nil {
                currentMask = 2
            } else if suffix.range(of: #"^\s*\.xy\b"#, options: .regularExpression) != nil {
                currentMask = 3
            } else if suffix.range(of: #"^\s*\."#, options: .regularExpression) != nil {
                return "unproven"
            } else {
                observesWholeVector = true
                currentMask = 0
            }
            componentMask |= currentMask
        }
        if observesWholeVector { return "wholeVector" }
        switch componentMask {
        case 1: return "redOnly"
        case 2: return "greenOnly"
        case 3: return "redGreenOnly"
        default: return "unproven"
        }
    }

    private static func normalizeUniformStruct(
        _ source: String,
        layout: ReflectedLayout,
        fieldNames: [String: String]
    ) throws -> String {
        let found = matches(#"(?s)struct\s+MWXUniforms\s*\{(.*?)\};"#, in: source)
        guard found.count == 1,
              let bodyRange = Range(found[0].range(at: 1), in: source) else {
            throw Failure.uniformStruct
        }
        let declarations = layout.fields.compactMap { field -> String? in
            guard let type = SceneAuthoredShaderValueType(rawValue: field.type) else {
                return nil
            }
            let suffix = field.arrayCount.map { "[\($0)]" } ?? ""
            return "    \(type.metalName) \(field.name)\(suffix);"
        }
        guard declarations.count == layout.fields.count else {
            throw Failure.uniformMember
        }
        let body = "\n" + declarations.joined(separator: "\n") + "\n"
        var result = source
        result.replaceSubrange(bodyRange, with: body)
        for (authoredName, fieldName) in fieldNames where authoredName != fieldName {
            result = result.replacingOccurrences(
                of: #"\."# + escaped(authoredName) + #"\b"#,
                with: ".\(fieldName)",
                options: .regularExpression
            )
        }
        for field in layout.fields where field.arrayCount != nil {
            result = result.replacingOccurrences(
                of: #"("# + escaped(field.name)
                    + #"\s*\[[^\]\r\n]+\])\.x\b"#,
                with: "$1",
                options: .regularExpression
            )
        }
        return result
    }

    private static func deduplicateStageHelper(
        vertex: String,
        fragment: String
    ) throws -> (String, String) {
        let pattern = #"(?s)template<typename T, size_t Num>\s+struct spvUnsafeArray\s*\{.*?\n\};"#
        let vertexMatch = matches(pattern, in: vertex).first
        let fragmentMatch = matches(pattern, in: fragment).first
        guard let vertexMatch, let fragmentMatch,
              let vertexHelper = substring(vertexMatch.range, in: vertex),
              let fragmentHelper = substring(fragmentMatch.range, in: fragment) else {
            return (vertex, fragment)
        }
        guard vertexHelper == fragmentHelper,
              let range = Range(fragmentMatch.range, in: fragment) else {
            throw Failure.stageHelperConflict
        }
        var result = fragment
        result.removeSubrange(range)
        return (vertex, result)
    }

    private static func align(_ value: Int, to alignment: Int) -> Int {
        (value + alignment - 1) / alignment * alignment
    }

    private static func closingParenthesis(
        in source: String,
        from opening: String.Index
    ) -> String.Index? {
        var depth = 0
        var cursor = opening
        while cursor < source.endIndex {
            switch source[cursor] {
            case "(": depth += 1
            case ")":
                depth -= 1
                if depth == 0 { return source.index(after: cursor) }
            default: break
            }
            cursor = source.index(after: cursor)
        }
        return nil
    }

    static func countWord(_ word: String, in source: String) -> Int {
        matches(#"\b"# + escaped(word) + #"\b"#, in: source).count
    }

    static func containsWord(_ word: String, in source: String) -> Bool {
        countWord(word, in: source) > 0
    }

    static func artifactTransfer(
        kind: String,
        slot: Int? = nil
    ) -> SceneGenericShaderProgramArtifact.Program.ColorTransfer {
        .init(kind: kind, slot: slot, slots: nil)
    }

    static func regexMatches(_ pattern: String, _ source: String) -> Bool {
        regex(pattern).firstMatch(in: source, range: fullRange(source)) != nil
    }

    static func captures(_ pattern: String, in source: String) -> [String]? {
        guard let match = regex(pattern).firstMatch(in: source, range: fullRange(source)) else {
            return nil
        }
        return (1 ..< match.numberOfRanges).compactMap { capture(match, $0, in: source) }
    }

    static func capturesAll(
        _ pattern: String,
        in source: String,
        group: Int
    ) -> [String] {
        matches(pattern, in: source).compactMap { capture($0, group, in: source) }
    }

    static func matches(_ pattern: String, in source: String) -> [NSTextCheckingResult] {
        regex(pattern).matches(in: source, range: fullRange(source))
    }

    private static func regex(_ pattern: String) -> NSRegularExpression {
        // Patterns are fixed implementation contracts, never authored input.
        try! NSRegularExpression(pattern: pattern)
    }

    private static func fullRange(_ source: String) -> NSRange {
        NSRange(source.startIndex..., in: source)
    }

    static func escaped(_ source: String) -> String {
        NSRegularExpression.escapedPattern(for: source)
    }

    static func substring(_ range: NSRange, in source: String) -> String? {
        guard let range = Range(range, in: source) else { return nil }
        return String(source[range])
    }

    static func capture(
        _ match: NSTextCheckingResult,
        _ index: Int,
        in source: String
    ) -> String? {
        guard index < match.numberOfRanges,
              match.range(at: index).location != NSNotFound,
              let range = Range(match.range(at: index), in: source) else { return nil }
        return String(source[range])
    }
}
