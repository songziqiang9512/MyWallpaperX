import Foundation

/// Converts the ordinary Wallpaper Engine GLSL-like declaration surface into
/// linked Vulkan GLSL. Every accepted rule is structural and source-driven;
/// unknown declarations or interface shapes fail closed before a helper runs.
nonisolated enum SceneGenericShaderSourceNormalizer {
    struct Pair {
        let vertex: String
        let fragment: String
        let localizedMutableFragmentVaryings: Set<String>
        let activeAudioSpectrumArrays: Set<String>
    }

    enum Failure: Error, Equatable {
        case sourceTooLarge
        case declarationUnsupported
        case declarationDuplicate
        case arrayUnsupported
        case uniformUnsupported
        case samplerUnsupported
        case attributeUnsupported
        case varyingUnsupported
        case stageLinkMismatch
        case reservedUniform
        case vertexMain
    }

    struct Shape: Equatable {
        let type: String
        let count: Int?
    }

    private struct Declaration {
        let storage: String
        let type: String
        let name: String
        let count: Int?
    }

    private struct ParsedStage {
        var body: String
        let declarations: [Declaration]
    }

    private static let valueTypes = Set([
        "bool", "int", "uint", "float",
        "ivec2", "ivec3", "ivec4",
        "uvec2", "uvec3", "uvec4",
        "vec2", "vec3", "vec4", "mat2", "mat3", "mat4",
    ])
    private static let declaration = try! NSRegularExpression(pattern:
        #"^\s*(uniform|attribute|varying)\s+([A-Za-z_][A-Za-z0-9_]*)\s+([A-Za-z_][A-Za-z0-9_]*)(?:\s*\[\s*([0-9]+)\s*\])?\s*;(?:\s*//.*)?$"#
    )

    static func normalize(
        vertexSource: String,
        fragmentSource: String,
        maximumStageSourceBytes: Int
    ) -> Result<Pair, Failure> {
        guard !vertexSource.isEmpty, !fragmentSource.isEmpty,
              vertexSource.utf8.count <= maximumStageSourceBytes,
              fragmentSource.utf8.count <= maximumStageSourceBytes,
              !vertexSource.contains("\0"), !fragmentSource.contains("\0") else {
            return .failure(.sourceTooLarge)
        }
        do {
            let typedVertexSource = rewriteFloatArrayIndices(
                rewriteAssignmentVectorConversions(
                    SceneGenericShaderDirectFunctionVectorArgumentNormalizer.rewriteUsingBoundedSyntax(
                        SceneGenericShaderScalarArithmeticNormalizer.rewrite(
                            vertexSource,
                            stage: .vertex
                        ),
                        stage: .vertex
                    ),
                    stage: .vertex
                )
            )
            let typedFragmentSource = rewriteFloatArrayIndices(
                rewriteAssignmentVectorConversions(
                    SceneGenericShaderDirectFunctionVectorArgumentNormalizer.rewriteUsingBoundedSyntax(
                        SceneGenericShaderScalarArithmeticNormalizer.rewrite(
                            fragmentSource,
                            stage: .fragment
                        ),
                        stage: .fragment
                    ),
                    stage: .fragment
                )
            )
            var parsed: [String: ParsedStage] = [
                "vertex": try parse(typedVertexSource),
                "fragment": try parse(typedFragmentSource),
            ]
            var uniforms: [String: Shape] = [:]
            var samplers: [String: Int] = [:]
            var attributes: [String: Shape] = [:]
            var stageVaryingShapes: [String: [String: Shape]] = [
                "vertex": [:], "fragment": [:],
            ]
            var stageVaryings: [String: Set<String>] = [
                "vertex": [], "fragment": [],
            ]
            for stage in ["vertex", "fragment"] {
                guard let value = parsed[stage] else { throw Failure.stageLinkMismatch }
                for item in value.declarations {
                    let shape = Shape(type: item.type, count: item.count)
                    switch item.storage {
                    case "uniform":
                        if item.type.hasPrefix("sampler") {
                            guard item.type == "sampler2D", item.count == nil,
                                  let slot = textureSlot(item.name) else {
                                throw Failure.samplerUnsupported
                            }
                            if let previous = samplers[item.name], previous != slot {
                                throw Failure.samplerUnsupported
                            }
                            samplers[item.name] = slot
                        } else {
                            guard valueTypes.contains(item.type),
                                  item.count == nil || isAudioSpectrumArray(item) else {
                                throw Failure.uniformUnsupported
                            }
                            try insert(shape, name: item.name, into: &uniforms,
                                       failure: .uniformUnsupported)
                        }
                    case "attribute":
                        guard stage == "vertex", item.count == nil,
                              valueTypes.contains(item.type) else {
                            throw Failure.attributeUnsupported
                        }
                        try insert(shape, name: item.name, into: &attributes,
                                   failure: .attributeUnsupported)
                    case "varying":
                        guard valueTypes.contains(item.type),
                              item.count.map({ (1 ... 16).contains($0) }) ?? true else {
                            throw Failure.varyingUnsupported
                        }
                        // A fragment declaration that is never referenced is
                        // not part of the linked stage interface. Some authored
                        // variants retain a wider optional declaration after
                        // preprocessing; rejecting it against the live vertex
                        // output would let dead metadata revoke the shader.
                        // Live declarations still enter the shared shape table
                        // below, so an actual ABI mismatch remains fail-closed.
                        if stage == "fragment",
                           (!containsWord(item.name, in: value.body)
                            || hasLocalDeclaration(item.name, in: value.body)) {
                            continue
                        }
                        try insert(shape, name: item.name, into: &stageVaryingShapes[stage]!,
                                   failure: .varyingUnsupported)
                        stageVaryings[stage, default: []].insert(item.name)
                    default:
                        throw Failure.declarationUnsupported
                    }
                }
            }
            // An `attribute vec3 a_TexCoord` whose vertex body only reads
            // `.xy` is dead metadata: the generated Metal wrapper supplies a
            // float2 texcoord and the `.xy` swizzle keeps its meaning.
            if attributes.count == 2,
               attributes["a_Position"] == Shape(type: "vec3", count: nil),
               attributes["a_TexCoord"] == Shape(type: "vec3", count: nil),
               bodyUsesOnlyXYComponentAccess(
                   "a_TexCoord", in: parsed["vertex"]?.body ?? ""
               ) {
                attributes["a_TexCoord"] = Shape(type: "vec2", count: nil)
            }
            guard attributes == [
                "a_Position": Shape(type: "vec3", count: nil),
                "a_TexCoord": Shape(type: "vec2", count: nil),
            ] else { throw Failure.attributeUnsupported }
            guard stageVaryings["fragment", default: []]
                .isSubset(of: stageVaryings["vertex", default: []]) else {
                throw Failure.stageLinkMismatch
            }
            let vertexVaryings = stageVaryingShapes["vertex", default: [:]]
            let fragmentVaryings = stageVaryingShapes["fragment", default: [:]]
            var varyingPrefixFacts: [
                String: SceneAuthoredShaderVaryingPrefixLink.Fact
            ] = [:]
            for name in stageVaryings["fragment", default: []] {
                guard let vertexShape = vertexVaryings[name],
                      let fragmentShape = fragmentVaryings[name] else {
                    throw Failure.stageLinkMismatch
                }
                if vertexShape == fragmentShape { continue }
                guard vertexShape.count == nil, fragmentShape.count == nil,
                      let vertexWidth = floatVectorWidth(vertexShape.type),
                      let fragmentWidth = floatVectorWidth(fragmentShape.type),
                      let vertexBody = parsed["vertex"]?.body,
                      let fragmentBody = parsed["fragment"]?.body,
                      let fact = SceneAuthoredShaderVaryingPrefixLink.prove(
                          name: name,
                          vertexWidth: vertexWidth,
                          fragmentWidth: fragmentWidth,
                          vertexSource: vertexBody,
                          fragmentSource: fragmentBody
                      ) else { throw Failure.varyingUnsupported }
                varyingPrefixFacts[name] = fact
            }
            let varyings = vertexVaryings
            guard uniforms["mwxRenderSize"] == nil,
                  uniforms.keys.allSatisfy({
                      SceneMaterialTextureTransformABI.component(forFieldName: $0) == nil
                  }) else { throw Failure.reservedUniform }

            guard var vertex = parsed["vertex"], var fragment = parsed["fragment"] else {
                throw Failure.stageLinkMismatch
            }
            fragment.body = SceneAuthoredShaderVaryingPrefixLink
                .rewriteWholeFragmentReferences(
                    fragment.body,
                    facts: varyingPrefixFacts
                )
            let expressionShapes = varyings.merging(uniforms) { current, _ in current }
            vertex.body = SceneGenericShaderDirectFunctionVectorArgumentNormalizer.rewrite(
                vertex.body,
                shapes: attributes.merging(expressionShapes) { current, _ in current }
            )
            fragment.body = SceneGenericShaderDirectFunctionVectorArgumentNormalizer.rewrite(
                fragment.body,
                shapes: expressionShapes
            )
            vertex.body = rewriteComponentWiseBuiltInAssignmentResults(
                vertex.body,
                shapes: expressionShapes
            )
            fragment.body = rewriteComponentWiseBuiltInAssignmentResults(
                fragment.body,
                shapes: expressionShapes
            )
            vertex.body = replaceWord("sample", with: "mwx_sample", in: vertex.body)
            fragment.body = replaceWord("sample", with: "mwx_sample", in: fragment.body)
            fragment.body = replaceWord("gl_FragColor", with: "mwxFragColor", in: fragment.body)
            vertex.body = rewriteTextureCoordinates(
                vertex.body,
                shapes: attributes.merging(varyings) { current, _ in current }
                    .merging(uniforms) { current, _ in current }
            )
            fragment.body = rewriteTextureCoordinates(
                fragment.body,
                shapes: varyings.merging(uniforms) { current, _ in current }
            )
            fragment.body = rewriteVector2ArithmeticOperands(
                fragment.body,
                shapes: varyings.merging(uniforms) { current, _ in current }
            )
            fragment.body = SceneGenericShaderTextureSamplingNormalizer
                .rewrite(fragment.body)
            fragment.body = rewriteScalarVectorAssignments(
                fragment.body,
                shapes: varyings.merging(uniforms) { current, _ in current }
            )
            fragment.body = rewriteVectorConstructorAssignments(
                fragment.body,
                shapes: varyings.merging(uniforms) { current, _ in current }
            )
            fragment.body = rewriteFloatToIntAssignments(
                fragment.body,
                shapes: varyings.merging(uniforms) { current, _ in current }
            )
            fragment.body = rewriteVectorClampLiteralArguments(fragment.body)
            guard let mutableVaryings = SceneGenericShaderMutableFragmentVaryingNormalizer
                .rewrite(
                    fragment.body,
                    varyings: varyings.mapValues {
                        .init(type: $0.type, count: $0.count)
                    }
                ) else {
                throw Failure.varyingUnsupported
            }
            fragment.body = mutableVaryings.source
            let usesTargetPixelPosition = containsWord(
                "g_ModelViewProjectionMatrix", in: vertex.body
            )
            guard let injected = injectVertexMain(
                vertex.body,
                usesTargetPixelPosition: usesTargetPixelPosition
            ) else {
                throw Failure.vertexMain
            }
            vertex.body = pruneUnusedVaryingComponentAssignments(
                injected,
                fragmentBody: fragment.body,
                varyings: varyings
            )
            parsed["vertex"] = vertex
            parsed["fragment"] = fragment

            let activeUniforms = uniforms.keys.filter { name in
                [vertex.body, fragment.body].contains { containsWord(name, in: $0) }
            }.sorted()
            let activeSamplerSlots = samplers.compactMap { name, slot in
                [vertex.body, fragment.body].contains { containsWord(name, in: $0) }
                    ? slot : nil
            }.sorted()
            let uniformLines = activeUniforms.map { name in
                let shape = uniforms[name]!
                let suffix = shape.count.map { "[\($0)]" } ?? ""
                return "    \(shape.type) \(name)\(suffix);"
            } + ["    vec2 mwxRenderSize;"]
                + SceneGenericShaderTextureSamplingNormalizer.uniformLines(
                    activeSlots: activeSamplerSlots
                )
            let varyingOrder = varyings.keys.sorted()
            var nextLocation = 0
            var locations: [String: Int] = [:]
            for name in varyingOrder {
                locations[name] = nextLocation
                nextLocation += varyings[name]?.count ?? 1
            }
            func source(stage: String, value: ParsedStage) -> String {
                let samplerLines = samplers.sorted(by: { $0.value < $1.value }).compactMap {
                    containsWord($0.key, in: value.body)
                        ? "layout(set = 0, binding = \($0.value)) uniform sampler2D \($0.key);"
                        : nil
                }
                var interface = varyingOrder.compactMap { name -> String? in
                    guard stageVaryings[stage, default: []].contains(name),
                          let shape = varyings[name], let location = locations[name] else {
                        return nil
                    }
                    let direction = stage == "vertex" ? "out" : "in"
                    let suffix = shape.count.map { "[\($0)]" } ?? ""
                    return "layout(location = \(location)) \(direction) \(shape.type) \(name)\(suffix);"
                }
                if stage == "fragment" {
                    interface.append("layout(location = 0) out vec4 mwxFragColor;")
                }
                return ([
                    "#version 450",
                    "#define mul(x, y) ((y) * (x))",
                    "#define CAST2(x) vec2(x)",
                    "#define CAST3(x) vec3(x)",
                    "#define CAST4(x) vec4(x)",
                    "#define CAST3X3(x) mat3(x)",
                    "#define frac fract",
                    "#define saturate(x) clamp((x), 0.0, 1.0)",
                    "#define atan2 atan",
                    "layout(std140, set = 0, binding = 8) uniform MWXUniforms {",
                ] + uniformLines + ["};"]
                    + SceneGenericShaderTextureSamplingNormalizer.supportLines(
                        activeSlots: activeSamplerSlots
                    )
                    + samplerLines + interface + [value.body])
                    .joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
            }
            let activeAudioSpectrumArrays = Set(activeUniforms.filter { name in
                guard let declaration = [vertex, fragment]
                    .flatMap(\.declarations)
                    .first(where: { $0.name == name }) else { return false }
                return isAudioSpectrumArray(declaration)
            })
            return .success(.init(
                vertex: source(stage: "vertex", value: vertex),
                fragment: source(stage: "fragment", value: fragment),
                localizedMutableFragmentVaryings:
                    mutableVaryings.localizedNames,
                activeAudioSpectrumArrays: activeAudioSpectrumArrays
            ))
        } catch let failure as Failure {
            return .failure(failure)
        } catch {
            return .failure(.declarationUnsupported)
        }
    }

    private static func parse(_ source: String) throws -> ParsedStage {
        var kept: [String] = []
        var declarations: [Declaration] = []
        var seen = Set<String>()
        for line in source.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n") {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("#version") { continue }
            let range = NSRange(line.startIndex..., in: line)
            guard let match = declaration.firstMatch(in: line, range: range) else {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if ["uniform", "attribute", "varying"].contains(where: {
                    trimmed == $0 || trimmed.hasPrefix("\($0) ") || trimmed.hasPrefix("\($0)\t")
                }) { throw Failure.declarationUnsupported }
                kept.append(line)
                continue
            }
            let storage = capture(match, 1, in: line)
            let type = capture(match, 2, in: line)
            let name = capture(match, 3, in: line)
            let count = Int(capture(match, 4, in: line))
            if let count, !(1 ... 128).contains(count) { throw Failure.arrayUnsupported }
            guard seen.insert("\(storage)|\(name)").inserted else {
                throw Failure.declarationDuplicate
            }
            declarations.append(.init(storage: storage, type: type, name: name, count: count))
        }
        return .init(body: kept.joined(separator: "\n"), declarations: declarations)
    }

    private static func insert(
        _ shape: Shape,
        name: String,
        into values: inout [String: Shape],
        failure: Failure
    ) throws {
        if let previous = values[name], previous != shape { throw failure }
        values[name] = shape
    }

    private static func floatVectorWidth(_ type: String) -> Int? {
        guard type.hasPrefix("vec"), let width = Int(type.dropFirst(3)),
              (2 ... 4).contains(width) else { return nil }
        return width
    }

    private static func textureSlot(_ name: String) -> Int? {
        guard name.hasPrefix("g_Texture"),
              let slot = Int(name.dropFirst("g_Texture".count)),
              (0 ..< 8).contains(slot) else { return nil }
        return slot
    }

    private static func isAudioSpectrumArray(_ declaration: Declaration) -> Bool {
        guard declaration.type == "float", let count = declaration.count,
              [16, 32, 64].contains(count) else { return false }
        return declaration.name == "g_AudioSpectrum\(count)Left"
            || declaration.name == "g_AudioSpectrum\(count)Right"
    }

    private static func injectVertexMain(
        _ source: String,
        usesTargetPixelPosition: Bool
    ) -> String? {
        let regex = try! NSRegularExpression(pattern: #"\bvoid\s+main\s*\(\s*\)\s*\{"#)
        let range = NSRange(source.startIndex..., in: source)
        guard regex.numberOfMatches(in: source, range: range) == 1 else { return nil }
        let positionExpression = usesTargetPixelPosition
            ? "(mwxPosition - vec2(0.5)) * mwxRenderSize"
            : "mwxPosition * 2.0 - vec2(1.0)"
        return regex.stringByReplacingMatches(
            in: source,
            range: range,
            withTemplate: """
void main() {
    const vec2 mwxCoordinates[4] = vec2[4](
        vec2(0.0, 1.0), vec2(1.0, 1.0),
        vec2(0.0, 0.0), vec2(1.0, 0.0));
    vec2 a_TexCoord = mwxCoordinates[gl_VertexIndex];
    vec2 mwxPosition = vec2(a_TexCoord.x, 1.0 - a_TexCoord.y);
    vec3 a_Position = vec3(\(positionExpression), 0.0);
"""
        )
    }

    /// Some valid prepared programs exceed the bounded syntax analyzer's
    /// broader language envelope before this normalizer runs. Preserve the
    /// same typed conversion with a declaration-driven fallback: exactly one
    /// component-wise built-in result, exactly one wider declared vector
    /// width, and no user-defined overload of that built-in.
    private static func rewriteComponentWiseBuiltInAssignmentResults(
        _ source: String,
        shapes: [String: Shape]
    ) -> String {
        let pattern = #"\b(vec[23])\s+([A-Za-z_]\w*)\s*=\s*((abs|clamp|max|min|pow|saturate|smoothstep|step)\s*\([^;]+\))\s*;"#
        let matcher = try! NSRegularExpression(pattern: pattern)
        var result = source
        for match in matcher.matches(
            in: source,
            range: NSRange(source.startIndex..., in: source)
        ).reversed() {
            guard let targetRange = Range(match.range(at: 1), in: source),
                  let nameRange = Range(match.range(at: 2), in: source),
                  let expressionRange = Range(match.range(at: 3), in: source),
                  let functionRange = Range(match.range(at: 4), in: source),
                  let targetWidth = Int(source[targetRange].dropFirst(3)),
                  let fullRange = Range(match.range, in: result) else { continue }
            let function = String(source[functionRange])
            let declarationPattern = #"\b(?:bool|int|uint|float|[biu]?vec[2-4]|mat[2-4])\s+"#
                + NSRegularExpression.escapedPattern(for: function) + #"\s*\("#
            let declarationMatcher = try! NSRegularExpression(
                pattern: declarationPattern
            )
            guard declarationMatcher.firstMatch(
                in: source,
                range: NSRange(source.startIndex..., in: source)
            ) == nil else { continue }
            let expression = String(source[expressionRange])
            let widths = Set(shapes.compactMap { name, shape -> Int? in
                guard containsWord(name, in: expression),
                      shape.count == nil,
                      shape.type.hasPrefix("vec"),
                      let width = Int(shape.type.dropFirst(3)) else { return nil }
                return width
            })
            guard widths.count == 1, let sourceWidth = widths.first,
                  sourceWidth > targetWidth,
                  expressionIdentifiersAreKnown(
                      expression,
                      shapes: shapes,
                      builtIns: [function]
                  ) else { continue }
            let target = String(source[targetRange])
            let name = String(source[nameRange])
            let suffix = targetWidth == 2 ? "xy" : "xyz"
            result.replaceSubrange(
                fullRange,
                with: "\(target) \(name) = (\(expression)).\(suffix);"
            )
        }
        return result
    }

    private static func expressionIdentifiersAreKnown(
        _ expression: String,
        shapes: [String: Shape],
        builtIns: Set<String>
    ) -> Bool {
        let known = Set(shapes.keys).union(builtIns).union([
            "bool", "int", "uint", "float",
            "vec2", "vec3", "vec4", "mat2", "mat3", "mat4",
            "true", "false",
        ])
        let matcher = try! NSRegularExpression(pattern: #"\b[A-Za-z_]\w*\b"#)
        let range = NSRange(expression.startIndex..., in: expression)
        for match in matcher.matches(in: expression, range: range) {
            guard let tokenRange = Range(match.range, in: expression) else {
                return false
            }
            if tokenRange.lowerBound > expression.startIndex {
                let previous = expression.index(before: tokenRange.lowerBound)
                if expression[previous] == "." { continue }
            }
            guard known.contains(String(expression[tokenRange])) else { return false }
        }
        return true
    }

    /// Reuse the bounded frontend's typed assignment conversion around a
    /// complete expression. This covers source-proven vector shrinkage such
    /// as a vec3 built-in result assigned to vec2 without teaching the helper
    /// compiler a second type-inference rule.
    /// Every body occurrence of the attribute must read exactly `.xy`; a body
    /// with no occurrence is also safe (the declaration is dead metadata).
    private static func bodyUsesOnlyXYComponentAccess(
        _ name: String, in body: String
    ) -> Bool {
        guard !body.isEmpty else { return true }
        let code = lexicalMask(body)
        let pattern = #"\b"# + NSRegularExpression.escapedPattern(for: name) + #"\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return false
        }
        let matches = regex.matches(
            in: code,
            range: NSRange(code.startIndex..., in: code)
        )
        return matches.allSatisfy { match in
            guard let range = Range(match.range, in: code) else { return false }
            return code[range.upperBound...].prefix(3) == ".xy"
        }
    }

    private static func hasLocalDeclaration(_ name: String, in source: String) -> Bool {
        let types = valueTypes.map(NSRegularExpression.escapedPattern).joined(separator: "|")
        let regex = try! NSRegularExpression(pattern:
            #"\b(?:"# + types + #")\s+"#
                + NSRegularExpression.escapedPattern(for: name) + #"\b"#
        )
        let code = lexicalMask(source)
        return regex.firstMatch(
            in: code,
            range: NSRange(code.startIndex..., in: code)
        ) != nil
    }

    static func componentAlias(_ value: Character) -> Character {
        switch value {
        case "r": "x"
        case "g": "y"
        case "b": "z"
        case "a": "w"
        default: value
        }
    }

    static func capture(_ match: NSTextCheckingResult, _ index: Int, in source: String) -> String {
        guard index < match.numberOfRanges,
              let range = Range(match.range(at: index), in: source) else { return "" }
        return String(source[range])
    }
}
