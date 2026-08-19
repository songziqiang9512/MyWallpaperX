import Foundation

/// Converts the ordinary Wallpaper Engine GLSL-like declaration surface into
/// linked Vulkan GLSL. Every accepted rule is structural and source-driven;
/// unknown declarations or interface shapes fail closed before a helper runs.
nonisolated enum SceneGenericShaderSourceNormalizer {
    struct Pair {
        let vertex: String
        let fragment: String
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

    private struct Shape: Equatable {
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
            let typedVertexSource = rewriteBuiltInVectorArguments(
                vertexSource,
                stage: .vertex
            )
            let typedFragmentSource = rewriteBuiltInVectorArguments(
                fragmentSource,
                stage: .fragment
            )
            var parsed: [String: ParsedStage] = [
                "vertex": try parse(typedVertexSource),
                "fragment": try parse(typedFragmentSource),
            ]
            var uniforms: [String: Shape] = [:]
            var samplers: [String: Int] = [:]
            var attributes: [String: Shape] = [:]
            var varyings: [String: Shape] = [:]
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
                        try insert(shape, name: item.name, into: &varyings,
                                   failure: .varyingUnsupported)
                        stageVaryings[stage, default: []].insert(item.name)
                    default:
                        throw Failure.declarationUnsupported
                    }
                }
            }
            guard attributes == [
                "a_Position": Shape(type: "vec3", count: nil),
                "a_TexCoord": Shape(type: "vec2", count: nil),
            ] else { throw Failure.attributeUnsupported }
            guard stageVaryings["fragment", default: []]
                .isSubset(of: stageVaryings["vertex", default: []]) else {
                throw Failure.stageLinkMismatch
            }
            guard uniforms["mwxRenderSize"] == nil else { throw Failure.reservedUniform }

            guard var vertex = parsed["vertex"], var fragment = parsed["fragment"] else {
                throw Failure.stageLinkMismatch
            }
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
            fragment.body = rewriteScalarTextureAssignments(fragment.body)
            fragment.body = rewriteScalarVectorAssignments(
                fragment.body,
                shapes: varyings.merging(uniforms) { current, _ in current }
            )
            fragment.body = rewriteVectorConstructorAssignments(
                fragment.body,
                shapes: varyings.merging(uniforms) { current, _ in current }
            )
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
            let uniformLines = activeUniforms.map { name in
                let shape = uniforms[name]!
                let suffix = shape.count.map { "[\($0)]" } ?? ""
                return "    \(shape.type) \(name)\(suffix);"
            } + ["    vec2 mwxRenderSize;"]
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
                    "#define texSample2D texture",
                    "#define CAST2(x) vec2(x)",
                    "#define CAST3(x) vec3(x)",
                    "#define CAST4(x) vec4(x)",
                    "#define frac fract",
                    "#define saturate(x) clamp((x), 0.0, 1.0)",
                    "#define atan2 atan",
                    "layout(std140, set = 0, binding = 8) uniform MWXUniforms {",
                ] + uniformLines + ["};"] + samplerLines + interface + [value.body])
                    .joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
            }
            return .success(.init(
                vertex: source(stage: "vertex", value: vertex),
                fragment: source(stage: "fragment", value: fragment)
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

    private static func rewriteScalarTextureAssignments(_ source: String) -> String {
        let regex = try! NSRegularExpression(pattern:
            #"(\bfloat\s+[A-Za-z_][A-Za-z0-9_]*\s*=\s*)(texSample2D\([^;]+\))(\s*;)"#
        )
        return regex.stringByReplacingMatches(
            in: source,
            range: NSRange(source.startIndex..., in: source),
            withTemplate: "$1$2.r$3"
        )
    }

    /// Wallpaper Engine authored GLSL permits the established bounded frontend
    /// conversion where one `mix`/`lerp` color argument is wider than the
    /// other. Reuse that typed rule before Vulkan GLSL validation so the two
    /// compiler paths do not disagree about the same authored expression.
    /// Unknown expressions, weights, and user-defined built-ins remain
    /// untouched and therefore fail closed in the helper compiler.
    private static func rewriteBuiltInVectorArguments(
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
        let analysis = SceneAuthoredShaderSyntaxAnalyzer.analyze(
            lexerOutput: lexer,
            stage: stage
        )
        guard analysis.diagnostics.isEmpty, let unit = analysis.unit else {
            return normalized
        }

        var lineStarts = [0]
        var scalarOffset = 0
        for scalar in normalized.unicodeScalars {
            scalarOffset += 1
            if scalar == "\n" { lineStarts.append(scalarOffset) }
        }
        let insertions = unit.tokens.indices.compactMap { index -> (Int, String)? in
            let token = unit.tokens[index]
            guard token.kind == .identifier,
                  let suffix = SceneAuthoredShaderBuiltInVectorConversion.suffix(
                      forIdentifierAt: index,
                      in: unit.tokens,
                      unit: unit
                  ), token.line > 0, token.line <= lineStarts.count else {
                return nil
            }
            let end = lineStarts[token.line - 1] + token.column - 1
                + token.text.unicodeScalars.count
            guard end <= normalized.unicodeScalars.count else { return nil }
            return (end, ".\(suffix)")
        }.sorted { $0.0 > $1.0 }
        guard !insertions.isEmpty else { return normalized }

        var result = normalized
        for (offset, suffix) in insertions {
            let scalarIndex = result.unicodeScalars.index(
                result.unicodeScalars.startIndex,
                offsetBy: offset
            )
            guard let index = String.Index(scalarIndex, within: result) else {
                return normalized
            }
            result.insert(contentsOf: suffix, at: index)
        }
        return result
    }

    /// The authored sampler accepts a float2 coordinate, while the common
    /// shader ABI exposes several texture-coordinate varyings as vec4. Apply
    /// the existing narrowing rule only when the coordinate is a declared
    /// vector identifier; complex expressions remain untouched and fail closed
    /// in the helper compiler.
    private static func rewriteTextureCoordinates(
        _ source: String,
        shapes: [String: Shape]
    ) -> String {
        let regex = try! NSRegularExpression(pattern:
            #"\btexSample2D\(\s*(g_Texture[0-7])\s*,\s*([A-Za-z_][A-Za-z0-9_]*)\s*\)"#
        )
        var result = source
        for match in regex.matches(
            in: source,
            range: NSRange(source.startIndex..., in: source)
        ).reversed() {
            guard let textureRange = Range(match.range(at: 1), in: source),
                  let coordinateRange = Range(match.range(at: 2), in: source),
                  let coordinateShape = shapes[String(source[coordinateRange])],
                  ["vec3", "vec4"].contains(coordinateShape.type),
                  let fullRange = Range(match.range, in: result) else {
                continue
            }
            let texture = String(source[textureRange])
            let coordinate = String(source[coordinateRange])
            result.replaceSubrange(
                fullRange,
                with: "texSample2D(\(texture), \(coordinate).xy)"
            )
        }
        return result
    }

    private static func rewriteScalarVectorAssignments(
        _ source: String,
        shapes: [String: Shape]
    ) -> String {
        let regex = try! NSRegularExpression(pattern:
            #"\bfloat\s+[A-Za-z_][A-Za-z0-9_]*\s*=\s*([^;]+);"#
        )
        let vectorNames = shapes.compactMap { name, shape in
            ["vec2", "vec3", "vec4"].contains(shape.type) ? name : nil
        }
        guard !vectorNames.isEmpty else { return source }
        let vectorRegex = try! NSRegularExpression(pattern:
            #"\b(?:"# + vectorNames.map(NSRegularExpression.escapedPattern).joined(separator: "|") + #")\b"#
        )
        var result = source
        for match in regex.matches(
            in: source,
            range: NSRange(source.startIndex..., in: source)
        ).reversed() {
            guard let expressionRange = Range(match.range(at: 1), in: result) else { continue }
            let expression = String(result[expressionRange])
            guard vectorRegex.firstMatch(
                in: expression,
                range: NSRange(expression.startIndex..., in: expression)
            ) != nil,
            !expression.trimmingCharacters(in: .whitespaces).hasPrefix("vec") else { continue }
            result.replaceSubrange(expressionRange, with: "(\(expression)).x")
        }
        return result
    }

    private static func rewriteVectorConstructorAssignments(
        _ source: String,
        shapes: [String: Shape]
    ) -> String {
        let regex = try! NSRegularExpression(pattern:
            #"\b(vec[2-4])\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(vec[2-4])\s*\(([^;]*)\);"#
        )
        var result = source
        for match in regex.matches(
            in: source,
            range: NSRange(source.startIndex..., in: source)
        ).reversed() {
            guard let targetRange = Range(match.range(at: 1), in: source),
                  let nameRange = Range(match.range(at: 2), in: source),
                  let sourceRange = Range(match.range(at: 3), in: source),
                  let targetWidth = Int(source[targetRange].dropFirst(3)),
                  let sourceWidth = Int(source[sourceRange].dropFirst(3)),
                  sourceWidth > targetWidth,
                  let argumentsRange = Range(match.range(at: 4), in: source),
                  let range = Range(match.range, in: result) else { continue }
            let target = String(source[targetRange])
            let name = String(source[nameRange])
            let constructor = String(source[sourceRange])
            let arguments = String(source[argumentsRange])
            let suffix = targetWidth == 2 ? ".xy" : ".xyz"
            result.replaceSubrange(
                range,
                with: "\(target) \(name) = \(constructor)(\(arguments))\(suffix);"
            )
        }
        return result
    }

    private static func pruneUnusedVaryingComponentAssignments(
        _ source: String,
        fragmentBody: String,
        varyings: [String: Shape]
    ) -> String {
        var result = source
        for (name, shape) in varyings.sorted(by: { $0.key < $1.key }) {
            guard shape.count == nil, let width = Int(shape.type.dropFirst(3)),
                  shape.type.hasPrefix("vec"), (2 ... 4).contains(width) else { continue }
            let used = usedComponents(of: name, width: width, in: fragmentBody)
            let regex = try! NSRegularExpression(pattern:
                #"(?m)^[ \t]*"# + NSRegularExpression.escapedPattern(for: name)
                    + #"\.([xyzwrgba]{1,4})\s*=\s*([^;]*);[ \t]*$"#
            )
            let matches = regex.matches(
                in: result,
                range: NSRange(result.startIndex..., in: result)
            ).reversed()
            for match in matches {
                let swizzle = capture(match, 1, in: result)
                let expression = capture(match, 2, in: result)
                let assigned = Set(swizzle.map(componentAlias))
                guard assigned.isDisjoint(with: used), safeDeadExpression(expression),
                      let range = Range(match.range, in: result) else { continue }
                result.removeSubrange(range)
            }
        }
        return result
    }

    private static func usedComponents(of name: String, width: Int, in source: String) -> Set<Character> {
        let regex = try! NSRegularExpression(pattern:
            #"\b"# + NSRegularExpression.escapedPattern(for: name) + #"\b(?:\.([xyzwrgba]{1,4}))?"#
        )
        var used = Set<Character>()
        for match in regex.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
            let swizzle = capture(match, 1, in: source)
            if swizzle.isEmpty { return Set("xyzw".prefix(width)) }
            used.formUnion(swizzle.map(componentAlias))
        }
        return used
    }

    private static func safeDeadExpression(_ expression: String) -> Bool {
        guard !expression.contains("++"), !expression.contains("--") else { return false }
        let allowed = try! NSRegularExpression(pattern: #"^[A-Za-z0-9_.,()\s+\-*/]+$"#)
        guard allowed.firstMatch(
            in: expression,
            range: NSRange(expression.startIndex..., in: expression)
        )?.range.length == expression.utf16.count else { return false }
        let calls = try! NSRegularExpression(pattern: #"\b([A-Za-z_]\w*)\s*\("#)
        let constructors = Set(["float", "int", "uint", "vec2", "vec3", "vec4"])
        return calls.matches(
            in: expression,
            range: NSRange(expression.startIndex..., in: expression)
        ).allSatisfy { constructors.contains(capture($0, 1, in: expression)) }
    }

    private static func replaceWord(_ word: String, with replacement: String, in source: String) -> String {
        let regex = try! NSRegularExpression(pattern:
            #"\b"# + NSRegularExpression.escapedPattern(for: word) + #"\b"#
        )
        return regex.stringByReplacingMatches(
            in: source,
            range: NSRange(source.startIndex..., in: source),
            withTemplate: replacement
        )
    }

    private static func containsWord(_ word: String, in source: String) -> Bool {
        let regex = try! NSRegularExpression(pattern:
            #"\b"# + NSRegularExpression.escapedPattern(for: word) + #"\b"#
        )
        return regex.firstMatch(
            in: source,
            range: NSRange(source.startIndex..., in: source)
        ) != nil
    }

    private static func hasLocalDeclaration(_ name: String, in source: String) -> Bool {
        let types = valueTypes.map(NSRegularExpression.escapedPattern).joined(separator: "|")
        let regex = try! NSRegularExpression(pattern:
            #"\b(?:"# + types + #")\s+"#
                + NSRegularExpression.escapedPattern(for: name) + #"\b"#
        )
        return regex.firstMatch(
            in: source,
            range: NSRange(source.startIndex..., in: source)
        ) != nil
    }

    private static func componentAlias(_ value: Character) -> Character {
        switch value {
        case "r": "x"
        case "g": "y"
        case "b": "z"
        case "a": "w"
        default: value
        }
    }

    private static func capture(_ match: NSTextCheckingResult, _ index: Int, in source: String) -> String {
        guard index < match.numberOfRanges,
              let range = Range(match.range(at: index), in: source) else { return "" }
        return String(source[range])
    }
}
