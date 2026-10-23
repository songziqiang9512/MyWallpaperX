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
        let vertexPositionInput: SceneAuthoredShaderProgram.VertexPositionInput
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
    static let sourceTypeAliases = SceneAuthoredShaderValueType.allCases.filter {
        $0.glslName != $0.rawValue && SceneAuthoredShaderValueType(authoredName: $0.rawValue) == $0
    }.map(\.rawValue)
    private static let declaration = try! NSRegularExpression(pattern:
        // Trailing whitespace after the terminator is insignificant authored
        // noise, not an unsupported declaration: a real workshop shader
        // (`varying vec2 v_TexCoord; ` with no annotation) was rejected here
        // and lost its effect to the shared-backend fallback.
        #"^\s*(uniform|attribute|varying)\s+([A-Za-z_][A-Za-z0-9_]*)\s+([A-Za-z_][A-Za-z0-9_]*)(?:\s*\.\s*[A-Za-z_][A-Za-z0-9_]*)?(?:\s*\[\s*([0-9]+)\s*\])?\s*;\s*(?://.*)?$"#
    )

    /// Product callers supply shared BackendCanonicalizer compiler sources.
    /// Scalar broadcast and floating-vector common-width conversions share
    /// the same token facts before interface and stage-link lowering.
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
            let dialectVertexSource = rewriteTypeSpellings(vertexSource, stage: .vertex)
            let dialectFragmentSource = rewriteTypeSpellings(fragmentSource, stage: .fragment)
            let typedVertexSource = rewriteFloatArrayIndices(
                rewriteAssignmentVectorConversions(
                    SceneGenericShaderDirectFunctionVectorArgumentNormalizer.rewriteUsingTypeSyntax(
                        SceneGenericShaderScalarArithmeticNormalizer.rewrite(
                            renameMetalReservedAlternativeTokens(dialectVertexSource)
                        ),
                        stage: .vertex
                    ),
                    stage: .vertex
                ), stage: .vertex
            )
            let typedFragmentSource = rewriteFloatArrayIndices(
                rewriteAssignmentVectorConversions(
                    SceneGenericShaderDirectFunctionVectorArgumentNormalizer.rewriteUsingTypeSyntax(
                        SceneGenericShaderScalarArithmeticNormalizer.rewrite(
                            renameMetalReservedAlternativeTokens(
                                stripHLSLAttributeAnnotations(dialectFragmentSource)
                            )
                        ),
                        stage: .fragment
                    ),
                    stage: .fragment
                ), stage: .fragment
            )
            let storageVertexSource = SceneGenericShaderRuntimeConstantNormalizer.rewrite(
                typedVertexSource, stage: .vertex)
            let storageFragmentSource = SceneGenericShaderRuntimeConstantNormalizer.rewrite(
                typedFragmentSource, stage: .fragment)
            let fragmentSourceForParsing = rewriteFragmentDerivativeCalls(storageFragmentSource)
            let parsedFragment = try parse(fragmentSourceForParsing, stage: "fragment")
            // Use the same deduplicated interface and unchanged body as stage
            // conversion. Identical fragment declarations are already allowed
            // by parse; they cannot make the shared scope analysis unavailable.
            let fragmentReferenceSource = parsedFragment.declarations.map {
                "\($0.storage) \($0.type) \($0.name)"
                    + ($0.count.map { "[\($0)]" } ?? "") + ";"
            }.joined(separator: "\n") + "\n" + parsedFragment.body
            let fragmentReferenceAnalysis = SceneAuthoredShaderSyntaxAnalyzer.analyzeForTypeConversions(
                lexerOutput: SceneAuthoredShaderLexer.lex(
                    source: fragmentReferenceSource,
                    stage: .fragment
                ),
                stage: .fragment
            )
            let fragmentReferenceUnit = fragmentReferenceAnalysis.diagnostics.isEmpty
                ? fragmentReferenceAnalysis.unit : nil
            var parsed: [String: ParsedStage] = [
                "vertex": try parse(storageVertexSource, stage: "vertex"),
                "fragment": parsedFragment,
            ]
            var uniforms: [String: Shape] = [:]
            var uniformStages: [String: String] = [:]
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
                                  let slot = SceneShaderSourceTextFacts.textureSlot(item.name) else {
                                throw Failure.samplerUnsupported
                            }
                            if let previous = samplers[item.name], previous != slot {
                                throw Failure.samplerUnsupported
                            }
                            samplers[item.name] = slot
                        } else {
                            guard valueTypes.contains(item.type),
                                  item.count == nil || isAudioSpectrumArray(item)
                                    || isEffectLightingArray(item) else {
                                throw Failure.uniformUnsupported
                            }
                            if let previous = uniforms[item.name], previous != shape {
                                guard let previousStage = uniformStages[item.name],
                                      let previousBody = parsed[previousStage]?.body else {
                                    throw Failure.uniformUnsupported
                                }
                                let previousIsLive = maskedContainsWord(item.name, in: previousBody)
                                let currentIsLive = maskedContainsWord(item.name, in: value.body)
                                guard !previousIsLive || !currentIsLive else {
                                    throw Failure.uniformUnsupported
                                }
                                if !currentIsLive { continue }
                            }
                            // Only a conflicting declaration whose name is
                            // absent from its stage body exits the merge.
                            // Shadowed names and member tokens remain live;
                            // no scope inference may change the shared ABI.
                            uniforms[item.name] = shape
                            uniformStages[item.name] = stage
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
                              item.count.map({
                                  (1 ... (item.type == "float" ? 32 : 16)).contains($0)
                              }) ?? true else {
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
                           (!SceneGenericShaderSourceNormalizer.maskedContainsWord(item.name, in: value.body)
                            || fragmentReferenceUnit.map({
                                !SceneAuthoredShaderGlobalReferenceAnalyzer.isReferenced(item.name, in: $0)
                            }) == true) {
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
            let expandedArrays = Set(vertexVaryings.filter {
                ($0.value.count ?? 0) > 16
            }.keys).union(fragmentVaryings.filter {
                ($0.value.count ?? 0) > 16
            }.keys)
            // Native generic arrays retain their complete linked shape. They
            // do not enter the bounded prefix/zero-fill or loop emitter paths.
            if !expandedArrays.isEmpty {
                guard expandedArrays.allSatisfy({ name in
                    vertexVaryings[name]?.type == "float"
                        && vertexVaryings[name] == fragmentVaryings[name]
                }), varyingComponentsFit(vertexVaryings),
                    varyingComponentsFit(fragmentVaryings) else {
                    throw Failure.varyingUnsupported
                }
            }
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
                  uniforms["mwxVertexCoordinates01"] == nil,
                  uniforms["mwxVertexCoordinates23"] == nil,
                  uniforms[SceneShaderColorBoundary.uniformName] == nil else {
                throw Failure.reservedUniform
            }

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
                shapes: attributes.merging(expressionShapes) { current, _ in current },
                convertsScalarArguments: false, convertsVectorArguments: true
            )
            fragment.body = SceneGenericShaderDirectFunctionVectorArgumentNormalizer.rewrite(
                fragment.body,
                shapes: expressionShapes,
                convertsScalarArguments: false, convertsVectorArguments: true
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
            // The authored fragment builtin observes raster position, while
            // the vertex builtin remains the clip-space output.
            fragment.body = replaceWord("gl_Position", with: "gl_FragCoord", in: fragment.body)
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
            fragment.body = rewriteVectorBuiltInIntFirstOperands(
                fragment.body,
                shapes: varyings.merging(uniforms) { current, _ in current }
            )
            fragment.body = rewriteVectorClampLiteralArguments(
                fragment.body,
                shapes: varyings.merging(uniforms) { current, _ in current }
            )
            // Prefix-link facts may promise zero-filled components; the fill
            // is part of the admission contract, so a failed append rejects
            // the shader instead of emitting undefined reads.
            guard let zeroFilled = SceneAuthoredShaderVaryingPrefixLink
                .appendVertexZeroFill(vertex.body, facts: varyingPrefixFacts) else {
                throw Failure.varyingUnsupported
            }
            vertex.body = zeroFilled
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
            let usesTargetPixelPosition = SceneGenericShaderSourceNormalizer.maskedContainsWord(
                "g_ModelViewProjectionMatrix", in: vertex.body
            )
            guard let injected = injectVertexMain(
                vertex.body,
                usesTargetPixelPosition: usesTargetPixelPosition
            ) else {
                throw Failure.vertexMain
            }
            vertex.body = injected
            parsed["vertex"] = vertex
            parsed["fragment"] = fragment

            let activeUniforms = uniforms.keys.filter { name in
                [vertex.body, fragment.body].contains { SceneGenericShaderSourceNormalizer.maskedContainsWord(name, in: $0) }
            }.sorted()
            let uniformLines = activeUniforms.map { name in
                let shape = uniforms[name]!
                let suffix = shape.count.map { "[\($0)]" } ?? ""
                return "    \(shape.type) \(name)\(suffix);"
            } + ["    vec2 mwxRenderSize;", "    vec4 mwxVertexCoordinates01;",
                 "    vec4 mwxVertexCoordinates23;"]
            let varyingOrder = varyings.keys.sorted()
            var nextLocation = 0
            var locations: [String: Int] = [:]
            for name in varyingOrder {
                locations[name] = nextLocation
                nextLocation += varyings[name]?.count ?? 1
            }
            func source(stage: String, value: ParsedStage) -> String {
                let samplerLines = samplers.sorted(by: { $0.value < $1.value }).compactMap {
                    SceneGenericShaderSourceNormalizer.maskedContainsWord($0.key, in: value.body)
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
                    // The backend language has no log10 builtin; the author
                    // producer is tone mapping's logarithmic curve. The
                    // component-wise expansion works for scalars and vectors.
                    "#define log10(x) (log(x) * 0.4342944819032518)",
                    // lerp is owned upstream by the scalar builtin literal
                    // rewriter (renamed to mix); rsqrt/exp10 are HLSL
                    // builtins with no GLSL counterpart and no rewriter
                    // owner. The corpus census found no authored definition
                    // of these names, so the macros cannot shadow one.
                    // exp10 routes through exp2 because GLSL pow has no
                    // scalar-first overload.
                    "#define rsqrt(x) (inversesqrt(x))",
                    "#define exp10(x) (exp2((x) * 3.3219280948873623))",
                    // fmod must keep the backend's trunc semantics: the
                    // result takes the sign of x, while GLSL mod takes the
                    // sign of y. The expansion is the HLSL formula verbatim
                    // (x - y*trunc(x/y)); the floor variant is the registered
                    // semantic trap and flips the sign in the mixed-sign
                    // quadrants. Both arguments divide by zero into NaN on
                    // both sides of the toolchain, so the edge matches. y is
                    // evaluated twice by the macro — harmless for the pure
                    // expressions GLSL arithmetic is, and the corpus call
                    // sites are pure; keep it that way.
                    "#define fmod(x, y) ((x) - (y) * trunc((x) / (y)))",
                    "layout(std140, set = 0, binding = 8) uniform MWXUniforms {",
                ] + uniformLines + ["};"]
                    + SceneGenericShaderTextureSamplingNormalizer.supportLines()
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
                activeAudioSpectrumArrays: activeAudioSpectrumArrays,
                vertexPositionInput: usesTargetPixelPosition ? .targetPixels : .clipSpace
            ))
        } catch let failure as Failure {
            return .failure(failure)
        } catch {
            return .failure(.declarationUnsupported)
        }
    }

    /// Fragment derivatives are authored under HLSL names. Rewrite calls, not
    /// symbols: a variable or author function named ddx/ddy keeps its identity.
    private static func rewriteFragmentDerivativeCalls(_ source: String) -> String {
        let masked = lexicalMask(source)
        let declarations = SceneShaderSourceTextFacts.matches(
            #"\b([A-Za-z_]\w*)\s+(ddx|ddy)\b"#,
            in: masked
        )
        var declaredNames = Set(declarations.compactMap { match -> String? in
            guard let type = SceneShaderSourceTextFacts.capture(match, 1, in: masked),
                  !["return", "else", "do", "case"].contains(type) else { return nil }
            return SceneShaderSourceTextFacts.capture(match, 2, in: masked)
        })
        // Comma declarators and other value references can shadow a builtin
        // without repeating its type. Keep an ambiguous name unchanged.
        declaredNames.formUnion(SceneShaderSourceTextFacts.matches(
            #"\b(ddx|ddy)\b(?!\s*\()"#, in: masked
        ).compactMap { SceneShaderSourceTextFacts.capture($0, 1, in: masked) })
        var result = source
        for match in SceneShaderSourceTextFacts.matches(
            #"\b(ddx|ddy)(?=\s*\()"#, in: masked
        ).reversed() {
            guard let range = Range(match.range, in: masked),
                  let replacement = Range(match.range, in: result),
                  !declaredNames.contains(String(masked[range])),
                  !hasMemberPrefix(before: range.lowerBound, in: masked) else { continue }
            result.replaceSubrange(replacement,
                with: masked[range] == "ddx" ? "dFdx" : "dFdy")
        }
        return result
    }

    private static func parse(
        _ source: String,
        stage: String
    ) throws -> ParsedStage {
        var kept: [String] = []
        var declarations: [Declaration] = []
        var seen: [String: Declaration] = [:]
        // The authoritative WE toolchain tolerated a repeated identical
        // varying declaration in the fragment stage (authored bundles
        // concatenate sources and may repeat the declaration). Keep the
        // first and drop the identical duplicate; a conflicting type or
        // array shape is rejected here.
        let duplicateVaryingAllowed = stage == "fragment"
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
            let count = Int(capture(match, 4, in: line))
            if let count, !(1 ... 128).contains(count) { throw Failure.arrayUnsupported }
            let kind: SceneShaderContract.StageKind = stage == "vertex" ? .vertex : .fragment
            let lexical = SceneAuthoredShaderLexer.lex(source: line, stage: kind)
            guard lexical.diagnostics.isEmpty,
                  let storage = SceneAuthoredShaderSyntaxUnit.Storage(
                    rawValue: capture(match, 1, in: line)
                  ),
                  let item = SceneAuthoredShaderSyntaxAnalyzer.declaration(
                    at: 0, storage: storage, tokens: lexical.tokens, stage: kind
                  ), item.range.upperBound == lexical.tokens.count else {
                throw Failure.declarationUnsupported
            }
            let type = item.typeName
            let name = item.name
            let storageName = storage.rawValue
            let value = Declaration(
                storage: storageName, type: type, name: name, count: item.arraySize
            )
            let identity = "\(storageName)|\(name)"
            if let previous = seen[identity] {
                // The authoritative toolchain tolerated a repeated identical
                // varying declaration in fragment sources (bundled shaders
                // concatenate stages); keep the first only when both value
                // type and array shape agree.
                if duplicateVaryingAllowed, storage == .varying,
                   previous.type == value.type, previous.count == value.count {
                    continue
                }
                throw Failure.declarationDuplicate
            }
            seen[identity] = value
            declarations.append(value)
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

    /// Conservative fragment-input budget shared by Apple7/M1 and newer.
    /// Existing arrays of at most 16 elements retain their original path.
    private static func varyingComponentsFit(_ shapes: [String: Shape]) -> Bool {
        var total = 0
        for shape in shapes.values {
            guard let type = SceneAuthoredShaderValueType(authoredName: shape.type) else {
                return false
            }
            let components: Int = switch type {
            case .bool, .int, .uint, .float: 1
            case .int2, .uint2, .float2: 2
            case .int3, .uint3, .float3: 3
            case .int4, .uint4, .float4, .float2x2: 4
            case .float3x3: 9
            case .float4x4: 16
            }
            let product = components.multipliedReportingOverflow(by: shape.count ?? 1)
            let sum = total.addingReportingOverflow(product.partialValue)
            guard !product.overflow, !sum.overflow, sum.partialValue <= 124 else {
                return false
            }
            total = sum.partialValue
        }
        return true
    }

    private static func isAudioSpectrumArray(_ declaration: Declaration) -> Bool {
        guard declaration.type == "float", let count = declaration.count,
              [16, 32, 64].contains(count) else { return false }
        return declaration.name == "g_AudioSpectrum\(count)Left"
            || declaration.name == "g_AudioSpectrum\(count)Right"
    }

    private static func isEffectLightingArray(_ declaration: Declaration) -> Bool {
        guard let type = SceneAuthoredShaderValueType(authoredName: declaration.type) else { return false }
        return SceneAuthoredShaderHostArrayShape.isEffectLighting(
            name: declaration.name, type: type, count: declaration.count
        )
    }

    /// Adapt the source's packed four-lane view to the unchanged N-float host
    /// ABI. Ordinary arrays and unknown consumers retain compiler rejection.
    static func rewriteAudioArrayViews(
        _ source: String, stage: SceneShaderContract.StageKind
    ) -> String {
        guard source.contains("g_AudioSpectrum") else { return source }
        let analysis = SceneAuthoredShaderSyntaxAnalyzer.analyzeForTypeConversions(
            lexerOutput: SceneAuthoredShaderLexer.lex(source: source, stage: stage), stage: stage
        )
        guard analysis.diagnostics.isEmpty, let unit = analysis.unit,
              !unit.tokens.contains(where: { $0.text == "struct" }) else { return source }
        let tokens = unit.tokens
        func stripped(_ initial: Range<Int>) -> Range<Int> {
            var range = initial
            while range.count >= 2, tokens[range.lowerBound].text == "(",
                  SceneAuthoredShaderSyntaxAnalyzer.matchingDelimiter(at: range.lowerBound, tokens: tokens)
                    == range.upperBound - 1 {
                range = (range.lowerBound + 1)..<(range.upperBound - 1)
            }
            return range
        }
        func parameter(in range: Range<Int>, operation: String) -> String? {
            guard let parts = SceneAuthoredShaderTokenScanner.split(
                stripped(range), separator: operation, tokens: tokens
            ), parts.count == 2 else { return nil }
            let left = stripped(parts[0]), right = stripped(parts[1])
            guard left.count == 1, right.count == 1,
                  tokens[left.lowerBound].kind == .identifier,
                  tokens[right.lowerBound].kind == .number,
                  Double(tokens[right.lowerBound].text) == 4 else { return nil }
            return tokens[left.lowerBound].text
        }
        var lineStarts = [0]
        for (offset, scalar) in source.unicodeScalars.enumerated() where scalar == "\n" {
            lineStarts.append(offset + 1)
        }
        let sourceScalars = Array(source.unicodeScalars)
        var edits: [(start: Int, end: Int, replacement: String)] = []
        func offset(_ index: Int, after: Bool = false) -> Int? {
            let token = tokens[index]
            guard token.line > 0, token.line <= lineStarts.count else { return nil }
            return lineStarts[token.line - 1] + token.column - 1
                + (after ? token.text.unicodeScalars.count : 0)
        }
        var helpers: [String: (declaration: Int, source: String)] = [:]
        for assignment in tokens.indices where tokens[assignment].text == "=" && assignment > 0 {
            guard tokens[assignment - 1].kind == .identifier,
                  assignment < 2 || tokens[assignment - 2].text != ".",
                  let function = unit.functions.first(where: { $0.bodyRange.contains(assignment) })
            else { continue }
            let exclusions = unit.functions.filter { $0 != function }.map {
                $0.headerRange.lowerBound..<$0.bodyRange.upperBound
            }
            let values = SceneAuthoredShaderSyntaxAnalyzer.consistentValueDeclarations(
                in: tokens, excluding: exclusions, before: assignment
            )
            guard values[tokens[assignment - 1].text]?.type == "float4" else { continue }
            var input = assignment + 1
            var parentheses: [Int] = []
            while input < function.bodyRange.upperBound, tokens[input].text == "(" {
                parentheses.append(input)
                input += 1
            }
            guard input + 1 < function.bodyRange.upperBound,
                  tokens[input].kind == .identifier, tokens[input + 1].text == "[",
                  let closing = SceneAuthoredShaderSyntaxAnalyzer.matchingDelimiter(
                      at: input + 1, tokens: tokens
                  ), closing < function.bodyRange.upperBound else { continue }
            var terminal = closing + 1
            var complete = true
            for opening in parentheses.reversed() {
                guard terminal < tokens.count, tokens[terminal].text == ")",
                      SceneAuthoredShaderSyntaxAnalyzer.matchingDelimiter(at: opening, tokens: tokens)
                        == terminal else { complete = false; break }
                terminal += 1
            }
            let declarations = unit.declarations.filter { $0.name == tokens[input].text }
            guard complete, terminal < tokens.count, tokens[terminal].text == ";",
                  declarations.count == 1, let declaration = declarations.first,
                  declaration.storage == .uniform,
                  isAudioSpectrumArray(.init(storage: "uniform", type: declaration.typeName,
                      name: declaration.name, count: declaration.arraySize)),
                  SceneAuthoredShaderGlobalReferenceAnalyzer.exactReferenceIndices(
                      declaration.name, in: unit
                  )?.contains(input) == true,
                  let row = SceneAuthoredShaderBuiltInVectorConversion.componentExpression(
                      (input + 2)..<closing, tokens: tokens, unit: unit
                  ), row.type == .int, row.conversions.isEmpty,
                  let first = offset(input), let last = offset(closing, after: true),
                  let opening = offset(input + 1),
                  let rowFirst = offset(input + 1, after: true), let rowLast = offset(closing),
                  let declarationEnd = declaration.range.last,
                  let insertion = offset(declarationEnd, after: true),
                  let count = declaration.arraySize else { continue }
            let helper = "mwxPackedAudio_\(declaration.name)"
            guard unit.defines[helper] == nil,
                  !tokens.contains(where: { $0.kind == .identifier && $0.text == helper })
            else { continue }
            guard first >= 0, last <= sourceScalars.count,
                  rowFirst >= 0, rowFirst < rowLast, rowLast < last,
                  sourceScalars[opening] == "[",
                  String(String.UnicodeScalarView(sourceScalars[first...]
                    .prefix(declaration.name.unicodeScalars.count))) == declaration.name,
                  sourceScalars[last - 1] == "]" else { continue }
            let rowSource = String(String.UnicodeScalarView(sourceScalars[rowFirst..<rowLast]))
            edits.append((first, last, "\(helper)(\(rowSource))"))
            helpers[helper] = (insertion, """

            vec4 \(helper)(int row) {
                if (row < 0 || row >= \(count / 4)) { return vec4(0.0); }
                int base = row * 4;
                return vec4(\(declaration.name)[base], \(declaration.name)[base + 1],
                    \(declaration.name)[base + 2], \(declaration.name)[base + 3]);
            }

            """)
        }
        for helper in helpers.sorted(by: { $0.key < $1.key }).map(\.value) {
            edits.append((helper.declaration, helper.declaration, helper.source))
        }
        for index in tokens.indices {
            guard let declaration = unit.declarations.first(where: { $0.name == tokens[index].text }),
                  declaration.storage == .uniform, declaration.typeName == "float",
                  let count = declaration.arraySize,
                  isAudioSpectrumArray(.init(storage: "uniform", type: "float",
                      name: declaration.name, count: count)),
                  index == 0 || tokens[index - 1].text != ".",
                  index + 1 < tokens.count, tokens[index + 1].text == "[",
                  let rowEnd = SceneAuthoredShaderSyntaxAnalyzer.matchingDelimiter(at: index + 1, tokens: tokens),
                  rowEnd + 1 < tokens.count, tokens[rowEnd + 1].text == "[",
                  let componentEnd = SceneAuthoredShaderSyntaxAnalyzer.matchingDelimiter(at: rowEnd + 1, tokens: tokens),
                  componentEnd + 1 >= tokens.count || tokens[componentEnd + 1].text != "[",
                  let bin = parameter(in: (index + 2)..<rowEnd, operation: "/"),
                  parameter(in: (rowEnd + 2)..<componentEnd, operation: "%") == bin,
                  let function = unit.functions.first(where: { $0.bodyRange.contains(index) }),
                  function.name != "main", function.returnType == "float",
                  unit.functions.filter({ $0.name == function.name }).count == 1,
                  function.parameterRange.count == 2,
                  tokens[function.parameterRange.lowerBound].text == "float",
                  tokens[function.parameterRange.lowerBound + 1].text == bin,
                  SceneAuthoredShaderSyntaxAnalyzer.uniqueValueDeclarations(
                      in: Array(tokens[function.parameterRange.lowerBound..<function.bodyRange.upperBound])
                  )[bin]?.type == "float",
                  !SceneAuthoredShaderSyntaxAnalyzer.valueDeclarationNames(
                      in: Array(tokens[function.bodyRange])
                  ).contains(declaration.name),
                  !SceneAuthoredShaderLoopAnalyzer.mutableArgumentNames(in: function.bodyRange, unit: unit).contains(bin),
                  !function.bodyRange.contains(where: { position in
                      tokens[position].text == bin && !SceneAuthoredShaderTokenScanner.isReadOnlyValueUse(
                          start: position, end: position + 1, tokens: tokens,
                          body: function.bodyRange, permitsReturn: true
                      )
                  }) else { continue }
            let first = tokens[index], last = tokens[componentEnd]
            guard first.line > 0, last.line > 0,
                  first.line <= lineStarts.count, last.line <= lineStarts.count else { continue }
            edits.append((lineStarts[first.line - 1] + first.column - 1,
                lineStarts[last.line - 1] + last.column - 1 + last.text.unicodeScalars.count,
                "\(declaration.name)[int(\(bin))]"))
        }
        var result = source
        for edit in edits.sorted(by: { $0.start > $1.start }) {
            let start = result.unicodeScalars.index(result.unicodeScalars.startIndex, offsetBy: edit.start)
            let end = result.unicodeScalars.index(result.unicodeScalars.startIndex, offsetBy: edit.end)
            guard let lower = String.Index(start, within: result), let upper = String.Index(end, within: result) else { return source }
            result.replaceSubrange(lower..<upper, with: edit.replacement)
        }
        return result
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
    vec2 mwxCoordinates[4] = vec2[4](
        mwxVertexCoordinates01.xy, mwxVertexCoordinates01.zw,
        mwxVertexCoordinates23.xy, mwxVertexCoordinates23.zw);
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
                guard SceneGenericShaderSourceNormalizer.maskedContainsWord(name, in: expression),
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

    static func capture(_ match: NSTextCheckingResult, _ index: Int, in source: String) -> String {
        guard index < match.numberOfRanges,
              let range = Range(match.range(at: index), in: source) else { return "" }
        return String(source[range])
    }
}
