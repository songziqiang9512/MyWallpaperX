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
            let uniformLayout = stagedUniforms.layout
            let color = try prepareColorTransfer(
                msl: fragmentStage.msl,
                authoredSource: fragmentStage.authoredSource
            )
            var vertexMSL = try normalizeUniformStruct(
                vertexStage.msl,
                layout: uniformLayout,
                fieldNames: stagedUniforms.vertexNames
            )
            var fragmentMSL = try normalizeUniformStruct(
                color.msl,
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
                metalSource: metalSource
            )
            guard colorTransfer(color.transfer, isBoundBy: bindings) else {
                throw Failure.colorTransfer
            }
            let loopWork: Int
            switch SceneGenericShaderBoundedLoopWork.evaluate(
                sources: stages.map(\.source)
            ) {
            case let .success(work):
                loopWork = work
            case .failure(.unbounded):
                throw Failure.loopUnbounded
            case .failure(.budget):
                throw Failure.loopBudget
            }
            let outputChannelUse = fragmentOutputChannelUse(
                fragmentStage.source
            )
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
                colorTransfer: color.transfer,
                fragmentOutputChannelUse: outputChannelUse.rawValue
            )
            return .success(.init(
                backendID: backendID,
                requestKey: requestKey,
                program: program
            ))
        } catch let failure as Failure {
            return .failure(failure)
        } catch {
            return .failure(.reflection)
        }
    }

    private static func fragmentOutputChannelUse(
        _ source: String
    ) -> SceneAuthoredShaderProgram.FragmentOutputChannelUse {
        let syntax = SceneAuthoredShaderSyntaxAnalyzer.analyze(
            lexerOutput: SceneAuthoredShaderLexer.lex(
                source: source,
                stage: .fragment
            ),
            stage: .fragment
        )
        guard let unit = syntax.unit, syntax.diagnostics.isEmpty else {
            return .unproven
        }
        return SceneAuthoredShaderFragmentOutputAnalyzer.analyze(unit)
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
        metalSource: String
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
        return try names.sorted(by: { $0.key < $1.key }).map { slot, name in
            let use = try channelUse(of: name, in: metalSource)
            return .init(name: name, slot: slot, channelUse: use)
        }
    }

    private static func channelUse(of name: String, in source: String) throws -> String {
        let marker = regex(#"\b"# + escaped(name) + #"\.sample\s*\("#)
        let matches = marker.matches(in: source, range: fullRange(source))
        guard !matches.isEmpty else { throw Failure.textureUnused }
        var channelUse: String?
        for match in matches {
            guard let range = Range(match.range, in: source),
                  let opening = source[range].lastIndex(of: "("),
                  let end = closingParenthesis(in: source, from: opening) else {
                return "unproven"
            }
            let suffix = source[end...]
            let current: String
            if suffix.range(of: #"^\s*\.x\b"#, options: .regularExpression) != nil {
                current = "redOnly"
            } else if suffix.range(of: #"^\s*\.xy\b"#, options: .regularExpression) != nil {
                current = "redGreenOnly"
            } else { return "unproven" }
            guard channelUse == nil || channelUse == current else { return "unproven" }
            channelUse = current
        }
        return channelUse ?? "unproven"
    }

    private static func prepareColorTransfer(
        msl source: String,
        authoredSource: String
    ) throws -> (
        msl: String,
        transfer: SceneGenericShaderProgramArtifact.Program.ColorTransfer
    ) {
        switch SceneAuthoredShaderColorTransferAnalyzer.analyze(
            fragmentSource: authoredSource
        ) {
        case let .passthrough(textureSlot: slot):
            return (source, artifactTransfer(kind: "passthrough", slot: slot))
        case let .interpolatedColor(textureSlots: slots):
            return (
                source,
                .init(kind: "interpolated-color", slot: nil, slots: slots)
            )
        case .opaque:
            return (source, artifactTransfer(kind: "opaque"))
        case .premultipliedAlpha:
            return (source, artifactTransfer(kind: "premultiplied"))
        case let .straightAlpha(textureSlot: expectedSlot):
            let weightedAverage = SceneAuthoredShaderAlphaWeightedSampleAverageAnalyzer
                .analyze(fragmentSource: authoredSource)
            let weightedLowering: String? = weightedAverage.flatMap { fact in
                guard fact.textureSlot == expectedSlot else { return nil }
                return SceneGenericShaderStraightAlphaPreservingLowering
                    .lowerAlphaWeightedSampleAverage(
                        source,
                        expectedSlot: expectedSlot,
                        sampleCount: fact.sampleCount
                    )
            }
            let requiresStraightColorBoundary =
                SceneAuthoredShaderColorTransferAnalyzer
                    .singleSamplerAlphaMutationSourceSlot(
                        fragmentSource: authoredSource
                    ) == expectedSlot
            let direct = straightAlphaAttenuation(
                source,
                requiresStraightColorBoundary: requiresStraightColorBoundary
            )
            let lowered = weightedLowering
                ?? (direct?.transfer.slot == expectedSlot ? direct?.msl : nil)
                ?? SceneGenericShaderStraightAlphaPreservingLowering
                    .lowerConditionalUnion(source, expectedSlot: expectedSlot)
                    ?? SceneGenericShaderStraightAlphaPreservingLowering
                        .lowerStraightOutput(source, expectedSlot: expectedSlot)
            guard let lowered else { throw Failure.colorTransfer }
            return (lowered, artifactTransfer(kind: "straight-alpha", slot: expectedSlot))
        case let .straightAlphaPreserving(textureSlot: expectedSlot):
            let preserving: (
                msl: String,
                transfer: SceneGenericShaderProgramArtifact.Program.ColorTransfer
            )?
            if let fact = SceneAuthoredShaderPreservedAlphaRGBFilterAnalyzer
                .analyze(fragmentSource: authoredSource) {
                guard fact.sourceSlot == expectedSlot,
                      let lowered = SceneGenericShaderStraightAlphaPreservingLowering
                        .lowerPreservedAlphaRGBFilter(
                            source,
                            fullColorSampleCallCounts:
                                fact.fullColorSampleCallCounts,
                            rgbColorSampleCallCounts:
                                fact.rgbColorSampleCallCounts,
                            dataSampleCallCounts: fact.dataSampleCallCounts
                        ) else { throw Failure.colorTransfer }
                preserving = (
                    msl: lowered,
                    transfer: artifactTransfer(
                        kind: "straight-alpha-preserving",
                        slot: expectedSlot
                    )
                )
            } else {
                preserving = straightAlphaPreserving(
                    source,
                    expectedSlot: expectedSlot
                )
            }
            guard let preserving else {
                throw Failure.colorTransfer
            }
            return preserving
        case .unresolved:
            // A compiler artifact may prove a form outside the bounded source
            // analyzer. The cache consumer still rejects any artifact that
            // contradicts a source fact that the shared analyzer did prove.
            return try prepareCompilerProvenColorTransfer(source)
        case .straightAlphaUNorm,
             .independentAlphaSignal,
             .independentAlphaSignalPreserving,
             .independentAlphaSignalCompositing:
            throw Failure.colorTransfer
        }
    }

    private static func prepareCompilerProvenColorTransfer(_ source: String) throws -> (
        msl: String,
        transfer: SceneGenericShaderProgramArtifact.Program.ColorTransfer
    ) {
        if let straight = straightAlphaAttenuation(source) { return straight }
        let assignments = matches(
            #"(?m)^[ \t]*out\.mwxFragColor\s*=.*;$"#,
            in: source
        )
        guard assignments.count == 1,
              let assignment = substring(assignments[0].range, in: source) else {
            throw Failure.colorTransfer
        }
        if let slotText = captures(
            #"^\s*out\.mwxFragColor\s*=\s*g_Texture([0-7])\.sample\([^;]+\);\s*$"#,
            in: assignment
        )?.first, let slot = Int(slotText) {
            return (
                source,
                SceneGenericShaderProgramArtifact.Program.ColorTransfer(
                    kind: "passthrough",
                    slot: slot,
                    slots: nil
                )
            )
        }
        if let interpolated = interpolatedColorTransfer(source, assignment: assignment) {
            return (source, interpolated)
        }
        if regexMatches(
            #"^\s*out\.mwxFragColor\s*=\s*float4\(.+,\s*1(?:\.0+)?\s*\);\s*$"#,
            assignment
        ) {
            return (
                source,
                SceneGenericShaderProgramArtifact.Program.ColorTransfer(
                    kind: "opaque",
                    slot: nil,
                    slots: nil
                )
            )
        }
        if premultipliedAccumulator(source, assignment: assignment) {
            return (
                source,
                SceneGenericShaderProgramArtifact.Program.ColorTransfer(
                    kind: "premultiplied",
                    slot: nil,
                    slots: nil
                )
            )
        }
        throw Failure.colorTransfer
    }

    private static func artifactTransfer(
        kind: String,
        slot: Int? = nil
    ) -> SceneGenericShaderProgramArtifact.Program.ColorTransfer {
        .init(kind: kind, slot: slot, slots: nil)
    }

    private static func colorTransfer(
        _ transfer: SceneGenericShaderProgramArtifact.Program.ColorTransfer,
        isBoundBy bindings: [
            SceneGenericShaderProgramArtifact.Program.TextureBinding
        ]
    ) -> Bool {
        let boundSlots = Set(bindings.map(\.slot))
        switch (transfer.kind, transfer.slot, transfer.slots) {
        case let ("passthrough", slot?, nil),
             let ("straight-alpha", slot?, nil),
             let ("straight-alpha-preserving", slot?, nil):
            return boundSlots.contains(slot)
        case let ("interpolated-color", nil, slots?):
            return slots.count >= 2
                && slots.count <= 8
                && slots == slots.sorted()
                && Set(slots).count == slots.count
                && Set(slots).isSubset(of: boundSlots)
        case ("opaque", nil, nil), ("premultiplied", nil, nil):
            return true
        default:
            return false
        }
    }

    private static func interpolatedColorTransfer(
        _ source: String,
        assignment: String
    ) -> SceneGenericShaderProgramArtifact.Program.ColorTransfer? {
        guard let output = captures(
            #"^\s*out\.mwxFragColor\s*=\s*mix\(\s*([A-Za-z_]\w*)\s*,\s*([A-Za-z_]\w*)\s*,\s*([^,)]+)\s*\)\s*;\s*$"#,
            in: assignment
        ), output.count == 3 else { return nil }

        var slots: [Int] = []
        for name in output.prefix(2) {
            let declarations = matches(
                #"(?m)^[ \t]*float4\s+"# + escaped(name)
                    + #"\s*=\s*g_Texture([0-7])\.sample\([^;]+\)\s*;$"#,
                in: source
            )
            guard declarations.count == 1,
                  let slotText = capture(declarations[0], 1, in: source),
                  let slot = Int(slotText),
                  countWord(name, in: source) == 2 else { return nil }
            slots.append(slot)
        }

        let weight = output[2].trimmingCharacters(in: .whitespacesAndNewlines)
        if !regexMatches(#"^[-+]?(?:\d+(?:\.\d*)?|\.\d+)$"#, weight) {
            guard matches(
                #"(?m)^[ \t]*float\s+"# + escaped(weight) + #"\s*=\s*[^;]+;$"#,
                in: source
            ).count == 1 else { return nil }
        }

        slots = Array(Set(slots)).sorted()
        guard slots.count >= 2 else { return nil }
        return .init(kind: "interpolated-color", slot: nil, slots: slots)
    }

    private static func straightAlphaAttenuation(
        _ source: String,
        requiresStraightColorBoundary: Bool = false
    ) -> (
        msl: String,
        transfer: SceneGenericShaderProgramArtifact.Program.ColorTransfer
    )? {
        let assignments = matches(
            #"(?m)^[ \t]*out\.mwxFragColor\s*=.*;$"#,
            in: source
        )
        guard assignments.count == 1,
              let assignment = substring(assignments[0].range, in: source),
              let name = captures(
                #"^[ \t]*out\.mwxFragColor\s*=\s*([A-Za-z_]\w*)\s*;$"#,
                in: assignment
              )?.first else { return nil }
        let namePattern = escaped(name)
        guard let slotText = captures(
            #"(?m)^[ \t]*float4\s+"# + namePattern
                + #"\s*=\s*g_Texture([0-7])\.sample\([^;]+\)\s*;$"#,
            in: source
        )?.first, let slot = Int(slotText) else { return nil }
        let attenuationPattern = #"(?m)^([ \t]*)"# + namePattern
            + #"\.w\s*\*=\s*([^;]+)\s*;$"#
        let attenuation = matches(attenuationPattern, in: source)
        guard attenuation.count == 1,
              let indent = capture(attenuation[0], 1, in: source),
              let factor = capture(attenuation[0], 2, in: source),
              !containsWord(name, in: factor) else { return nil }
        let writes = capturesAll(
            #"(?m)^\s*"# + namePattern
                + #"(?:\.([xyzwrgba]{1,4}))?\s*(?:[+\-*/]?=)"#,
            in: source,
            group: 1
        )
        guard writes == ["w"],
              countWord(name, in: source) == 3 + matches(
                  #"\b"# + namePattern + #"\.(?:[xyzrgb]{1,3})\b"#, in: source
              ).count,
              let replaceRange = Range(attenuation[0].range, in: source) else { return nil }
        if requiresStraightColorBoundary {
            guard let transformed =
                SceneGenericShaderStraightAlphaPreservingLowering
                    .lowerPreserving(source, expectedSlot: slot) else {
                return nil
            }
            return (
                transformed,
                SceneGenericShaderProgramArtifact.Program.ColorTransfer(
                    kind: "straight-alpha",
                    slot: slot,
                    slots: nil
                )
            )
        }
        var transformed = source
        transformed.replaceSubrange(replaceRange, with: "\(indent)\(name) *= \(factor);")
        return (
            transformed,
            SceneGenericShaderProgramArtifact.Program.ColorTransfer(
                kind: "straight-alpha",
                slot: slot,
                slots: nil
            )
        )
    }

    /// SPIRV-Cross samples the host's premultiplied color directly into the
    /// authored local. A source-proven alpha-preserving RGB flow must instead
    /// execute in straight color, then return to the compositor's
    /// premultiplied boundary. Both rewrites are required; emitting only the
    /// artifact tag would silently change translucent RGB math.
    private static func straightAlphaPreserving(
        _ source: String,
        expectedSlot: Int
    ) -> (
        msl: String,
        transfer: SceneGenericShaderProgramArtifact.Program.ColorTransfer
    )? {
        guard let transformed = SceneGenericShaderStraightAlphaPreservingLowering
            .lowerPreserving(source, expectedSlot: expectedSlot) else { return nil }
        return (
            transformed,
            SceneGenericShaderProgramArtifact.Program.ColorTransfer(
                kind: "straight-alpha-preserving",
                slot: expectedSlot,
                slots: nil
            )
        )
    }

    private static func premultipliedAccumulator(_ source: String, assignment: String) -> Bool {
        guard let name = captures(
            #"^\s*out\.mwxFragColor\s*=\s*([A-Za-z_]\w*)\s*;$"#,
            in: assignment
        )?.first else { return false }
        let n = escaped(name)
        guard regexMatches(#"float4\s+"# + n + #"\s*=\s*float4\(\s*0(?:\.0+)?\s*\)\s*;"#, source),
              regexMatches(
                #"float3\s+[A-Za-z_]\w*\s*\([^)]*thread\s+const\s+float3&[^)]*thread\s+const\s+float3&[^)]*thread\s+const\s+float&[^)]*\)\s*\{\s*return\s+([A-Za-z_]\w*)\s*\+\s*\(\s*([A-Za-z_]\w*)\s*\*\s*([A-Za-z_]\w*)\s*\)\s*;\s*\}"#,
                source
              ),
              regexMatches(#"\(\s*31\s*,"#, source),
              regexMatches(n + #"\.w\s*=\s*fast::max\(\s*"# + n + #"\.w\s*,"#, source) else {
            return false
        }
        return capturesAll(
            #"(?m)^\s*"# + n + #"\.([xyzw])\s*="#,
            in: source,
            group: 1
        ) == ["x", "y", "z", "w"]
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

    private static func countWord(_ word: String, in source: String) -> Int {
        matches(#"\b"# + escaped(word) + #"\b"#, in: source).count
    }

    private static func containsWord(_ word: String, in source: String) -> Bool {
        countWord(word, in: source) > 0
    }

    private static func regexMatches(_ pattern: String, _ source: String) -> Bool {
        regex(pattern).firstMatch(in: source, range: fullRange(source)) != nil
    }

    private static func captures(_ pattern: String, in source: String) -> [String]? {
        guard let match = regex(pattern).firstMatch(in: source, range: fullRange(source)) else {
            return nil
        }
        return (1 ..< match.numberOfRanges).compactMap { capture(match, $0, in: source) }
    }

    private static func capturesAll(
        _ pattern: String,
        in source: String,
        group: Int
    ) -> [String] {
        matches(pattern, in: source).compactMap { capture($0, group, in: source) }
    }

    private static func matches(_ pattern: String, in source: String) -> [NSTextCheckingResult] {
        regex(pattern).matches(in: source, range: fullRange(source))
    }

    private static func regex(_ pattern: String) -> NSRegularExpression {
        // Patterns are fixed implementation contracts, never authored input.
        try! NSRegularExpression(pattern: pattern)
    }

    private static func fullRange(_ source: String) -> NSRange {
        NSRange(source.startIndex..., in: source)
    }

    private static func escaped(_ source: String) -> String {
        NSRegularExpression.escapedPattern(for: source)
    }

    private static func substring(_ range: NSRange, in source: String) -> String? {
        guard let range = Range(range, in: source) else { return nil }
        return String(source[range])
    }

    private static func capture(
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
