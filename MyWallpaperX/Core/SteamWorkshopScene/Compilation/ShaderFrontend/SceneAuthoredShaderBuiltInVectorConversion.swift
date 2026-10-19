import Foundation

nonisolated enum SceneAuthoredShaderBuiltInVectorConversion {
    struct Conversion: Hashable {
        let range: Range<Int>
        let suffix: String
    }

    struct Expression {
        let range: Range<Int>
        let type: SceneAuthoredShaderValueType
        let conversions: [Conversion]
        let compound: Bool
        let directlyNarrowable: Bool
    }

    static func rewriteScalarVectorBroadcasts(
        _ source: String,
        stage: SceneShaderContract.StageKind
    ) -> String {
        rewriteScalarMinMaxIntegerLiterals(
            rewriteLiteralBoundBroadcasts(
                rewriteScalarPowBroadcasts(
                    rewriteScalarEndpointBroadcasts(source, stage: stage),
                    stage: stage
                ),
                stage: stage
            ),
            stage: stage
        )
    }

    static func suffix(
        forIdentifierAt index: Int,
        in tokens: [SceneAuthoredShaderToken],
        unit: SceneAuthoredShaderSyntaxUnit
    ) -> String? {
        guard tokens.indices.contains(index),
              tokens[index].kind == .identifier,
              let opening = enclosingCallOpening(for: index, in: tokens),
              opening > 0,
              ["mix", "lerp"].contains(tokens[opening - 1].text),
              !unit.functions.contains(where: { $0.name == tokens[opening - 1].text }),
              let closing = SceneAuthoredShaderTokenScanner.matchingParenthesis(tokens: tokens, opening: opening),
              let ranges = argumentRanges(opening: opening, closing: closing, tokens: tokens),
              ranges.count == 3,
              let argumentIndex = ranges.prefix(2).firstIndex(of: index..<(index + 1)),
              let first = standaloneType(
                  ranges[0], before: index, tokens: tokens, unit: unit
              ),
              let second = standaloneType(
                  ranges[1], before: index, tokens: tokens, unit: unit
              ),
              let firstWidth = floatVectorWidth(first),
              let secondWidth = floatVectorWidth(second),
              validWeight(
                  ranges[2], width: min(firstWidth, secondWidth),
                  before: index, tokens: tokens, unit: unit
              ) else { return nil }
        let sourceWidth = argumentIndex == 0 ? firstWidth : secondWidth
        return narrowingSuffix(from: sourceWidth, to: min(firstWidth, secondWidth))
    }

    /// Wallpaper Engine's authored shader surface permits a scalar color
    /// endpoint to be broadcast across the other floating-point vector
    /// endpoint of `mix`/`lerp`, and a scalar `smoothstep` bound beside a
    /// vector bound. Vulkan GLSL requires the mixed bounds to have the same
    /// shape. The smoothstep path also proves its vector input and caller
    /// scope; unknown shapes and authored overloads remain compiler-owned.
    static func rewriteScalarEndpointBroadcasts(
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

        var lineStarts = [0]
        var scalarOffset = 0
        for scalar in normalized.unicodeScalars {
            scalarOffset += 1
            if scalar == "\n" { lineStarts.append(scalarOffset) }
        }
        func tokenOffset(_ index: Int, afterToken: Bool) -> Int? {
            guard unit.tokens.indices.contains(index) else { return nil }
            let token = unit.tokens[index]
            guard token.line > 0, token.line <= lineStarts.count else { return nil }
            return lineStarts[token.line - 1] + token.column - 1
                + (afterToken ? token.text.unicodeScalars.count : 0)
        }

        var insertions: [(offset: Int, text: String)] = []
        for index in unit.tokens.indices {
            let name = unit.tokens[index].text
            guard ["mix", "lerp", "smoothstep"].contains(name),
                  !unit.functions.contains(where: {
                      $0.name == name
                  }), index + 1 < unit.tokens.count,
                  unit.tokens[index + 1].text == "(",
                  let closing = SceneAuthoredShaderTokenScanner.matchingParenthesis(
                      tokens: unit.tokens,
                      opening: index + 1
                  ),
                  let arguments = argumentRanges(
                      opening: index + 1,
                      closing: closing,
                      tokens: unit.tokens
                  ), arguments.count == 3 else { continue }
            let first: SceneAuthoredShaderValueType
            let second: SceneAuthoredShaderValueType
            if name == "smoothstep" {
                guard index == 0 || unit.tokens[index - 1].text != ".",
                      !SceneAuthoredShaderSyntaxAnalyzer.valueDeclarationNames(
                          in: unit.tokens
                      ).contains(name),
                      let caller = unit.functions.first(where: {
                          $0.bodyRange.contains(index)
                      }) else { continue }
                let values = SceneAuthoredShaderFunctionSemantics
                    .uniqueRootScopeValueDeclarations(for: caller, in: unit)
                    .filter { $0.value.index < index }
                    .compactMapValues {
                        SceneAuthoredShaderValueType(authoredName: $0.type)
                    }
                let expressions = arguments.compactMap {
                    componentExpression($0, tokens: unit.tokens, unit: unit,
                        valueTypes: values, permitsScalarVectorAddition: true)
                }
                guard expressions.count == 3,
                      expressions.allSatisfy({ $0.conversions.isEmpty }),
                      let width = floatVectorWidth(expressions[2].type),
                      expressions.prefix(2).allSatisfy({
                          $0.type == .float || floatVectorWidth($0.type) == width
                      }) else { continue }
                first = expressions[0].type
                second = expressions[1].type
            } else {
                guard let firstType = standaloneType(
                          arguments[0], before: index,
                          tokens: unit.tokens, unit: unit
                      ), let secondType = standaloneType(
                          arguments[1], before: index,
                          tokens: unit.tokens, unit: unit
                      ) else { continue }
                first = firstType
                second = secondType
            }
            let scalarRange: Range<Int>
            let vectorWidth: Int
            if first == .float, let width = floatVectorWidth(second) {
                scalarRange = arguments[0]
                vectorWidth = width
            } else if second == .float, let width = floatVectorWidth(first) {
                scalarRange = arguments[1]
                vectorWidth = width
            } else {
                continue
            }
            guard (2 ... 4).contains(vectorWidth),
                  let start = tokenOffset(scalarRange.lowerBound, afterToken: false),
                  let end = tokenOffset(scalarRange.upperBound - 1, afterToken: true)
            else { continue }
            insertions.append((start, "vec\(vectorWidth)("))
            insertions.append((end, ")"))
        }
        guard !insertions.isEmpty else { return normalized }

        var result = normalized
        for insertion in insertions.sorted(by: { lhs, rhs in
            if lhs.offset != rhs.offset { return lhs.offset > rhs.offset }
            if lhs.text != rhs.text { return lhs.text == ")" }
            return false
        }) {
            guard insertion.offset <= result.unicodeScalars.count else {
                return normalized
            }
            let scalarIndex = result.unicodeScalars.index(
                result.unicodeScalars.startIndex,
                offsetBy: insertion.offset
            )
            guard let stringIndex = String.Index(scalarIndex, within: result) else {
                return normalized
            }
            result.insert(contentsOf: insertion.text, at: stringIndex)
        }
        return result
    }

    /// HLSL broadcasts scalar bounds to the vector operand of min/max.
    /// Vulkan GLSL requires an explicit vector for the scalar-first form.
    private static func rewriteLiteralBoundBroadcasts(
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

        var lineStarts = [0]
        var scalarOffset = 0
        for scalar in normalized.unicodeScalars {
            scalarOffset += 1
            if scalar == "\n" { lineStarts.append(scalarOffset) }
        }
        func tokenOffset(_ index: Int, afterToken: Bool) -> Int? {
            guard unit.tokens.indices.contains(index) else { return nil }
            let token = unit.tokens[index]
            guard token.line > 0, token.line <= lineStarts.count else { return nil }
            return lineStarts[token.line - 1] + token.column - 1
                + (afterToken ? token.text.unicodeScalars.count : 0)
        }
        var replacements: [(start: Int, end: Int, text: String)] = []
        for index in unit.tokens.indices {
            let name = unit.tokens[index].text
            guard ["min", "max"].contains(name),
                  !unit.functions.contains(where: { $0.name == name }),
                  index + 1 < unit.tokens.count,
                  unit.tokens[index + 1].text == "(",
                  let closing = SceneAuthoredShaderTokenScanner.matchingParenthesis(
                      tokens: unit.tokens,
                      opening: index + 1
                  ),
                  let arguments = argumentRanges(
                      opening: index + 1,
                      closing: closing,
                      tokens: unit.tokens
                  ), arguments.count == 2,
                  arguments[0].count == 1,
                  unit.tokens[arguments[0].lowerBound].kind == .number,
                  let bound = Float(unit.tokens[arguments[0].lowerBound].text),
                  bound.isFinite,
                  let second = componentExpression(
                      arguments[1],
                      tokens: unit.tokens, unit: unit
                  ), second.conversions.isEmpty,
                  let vectorWidth = floatVectorWidth(second.type) else { continue }
            guard let start = tokenOffset(
                      arguments[0].lowerBound,
                      afterToken: false
                  ),
                  let end = tokenOffset(
                      arguments[0].upperBound - 1,
                      afterToken: true
                  ) else { continue }
            let literal = unit.tokens[arguments[0].lowerBound].text
            // Preserve octal syntax: appending .0 changes 010 (8) to 10.
            let floatingLiteral = Int(literal) == nil
                || (literal.count > 1 && literal.first == "0")
                ? literal : literal + ".0"
            replacements.append((start, end, "vec\(vectorWidth)(\(floatingLiteral))"))
        }
        guard !replacements.isEmpty else { return normalized }

        var result = normalized
        for replacement in replacements.sorted(by: { $0.start > $1.start }) {
            guard replacement.start <= replacement.end,
                  replacement.end <= result.unicodeScalars.count else {
                return normalized
            }
            let startScalar = result.unicodeScalars.index(
                result.unicodeScalars.startIndex,
                offsetBy: replacement.start
            )
            let endScalar = result.unicodeScalars.index(
                result.unicodeScalars.startIndex,
                offsetBy: replacement.end
            )
            guard let startIndex = String.Index(startScalar, within: result),
                  let endIndex = String.Index(endScalar, within: result) else {
                return normalized
            }
            result.replaceSubrange(startIndex..<endIndex, with: replacement.text)
        }
        return result
    }

    /// Wallpaper Engine's GLSL-like surface accepts an integer literal at a
    /// floating-point scalar `min`/`max` endpoint. Metal retains distinct
    /// integer and floating overloads, so the untyped literal makes the call
    /// ambiguous. Convert only a single integer literal whose peer is
    /// statically proven to be a scalar float expression. User overloads,
    /// integer domains, vectors, and unknown expressions remain untouched.
    private static func rewriteScalarMinMaxIntegerLiterals(
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
        let lexer = SceneAuthoredShaderLexer.lex(
            source: analysisSource,
            stage: stage
        )
        let analysis = SceneAuthoredShaderSyntaxAnalyzer.analyzeForTypeConversions(
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
        func tokenOffset(_ index: Int, afterToken: Bool) -> Int? {
            guard unit.tokens.indices.contains(index) else { return nil }
            let token = unit.tokens[index]
            guard token.line > 0, token.line <= lineStarts.count else {
                return nil
            }
            return lineStarts[token.line - 1] + token.column - 1
                + (afterToken ? token.text.unicodeScalars.count : 0)
        }
        var insertions: [(offset: Int, text: String)] = []
        for index in unit.tokens.indices {
            let name = unit.tokens[index].text
            guard ["min", "max"].contains(name),
                  !unit.functions.contains(where: { $0.name == name }),
                  index + 1 < unit.tokens.count,
                  unit.tokens[index + 1].text == "(",
                  let closing = SceneAuthoredShaderTokenScanner.matchingParenthesis(
                      tokens: unit.tokens,
                      opening: index + 1
                  ),
                  let arguments = argumentRanges(
                      opening: index + 1,
                      closing: closing,
                      tokens: unit.tokens
                  ), arguments.count == 2,
                  let first = componentExpression(
                      arguments[0], tokens: unit.tokens, unit: unit
                  ),
                  let second = componentExpression(
                      arguments[1], tokens: unit.tokens, unit: unit
                  ) else { continue }
            let literalRange: Range<Int>
            if first.type == .int, second.type == .float {
                literalRange = arguments[0]
            } else if first.type == .float, second.type == .int {
                literalRange = arguments[1]
            } else {
                continue
            }
            guard literalRange.count == 1,
                  unit.tokens[literalRange.lowerBound].kind == .number,
                  Int(unit.tokens[literalRange.lowerBound].text) != nil,
                  let end = tokenOffset(
                      literalRange.lowerBound,
                      afterToken: true
                  ) else { continue }
            let literal = unit.tokens[literalRange.lowerBound].text
            if literal.count > 1 && literal.first == "0" {
                guard let start = tokenOffset(
                    literalRange.lowerBound, afterToken: false
                ) else { continue }
                insertions.append((start, "float("))
                insertions.append((end, ")"))
            } else {
                insertions.append((end, ".0"))
            }
        }
        guard !insertions.isEmpty else { return normalized }

        var result = normalized
        for insertion in insertions.sorted(by: { $0.offset > $1.offset }) {
            guard insertion.offset <= result.unicodeScalars.count else {
                return normalized
            }
            let scalarIndex = result.unicodeScalars.index(
                result.unicodeScalars.startIndex,
                offsetBy: insertion.offset
            )
            guard let stringIndex = String.Index(
                scalarIndex,
                within: result
            ) else { return normalized }
            result.insert(contentsOf: insertion.text, at: stringIndex)
        }
        return result
    }

    static func addCompoundMixBoundaries(
        starts: inout [Int: Int],
        ends: inout [Int: [String]],
        tokens: [SceneAuthoredShaderToken],
        unit: SceneAuthoredShaderSyntaxUnit
    ) {
        let conversions = Set(tokens.indices.flatMap { index -> [Conversion] in
            guard tokens[index].text == "(", index > 0,
                  ["mix", "lerp"].contains(tokens[index - 1].text),
                  !unit.functions.contains(where: { $0.name == tokens[index - 1].text }),
                  let closing = SceneAuthoredShaderTokenScanner.matchingParenthesis(tokens: tokens, opening: index),
                  let ranges = argumentRanges(opening: index, closing: closing, tokens: tokens),
                  ranges.count == 3,
                  let first = componentExpression(ranges[0], tokens: tokens, unit: unit),
                  let second = componentExpression(ranges[1], tokens: tokens, unit: unit),
                  let firstWidth = floatVectorWidth(first.type),
                  firstWidth == floatVectorWidth(second.type) else { return [] }
            if validWeight(
                ranges[2], width: firstWidth, before: index,
                tokens: tokens, unit: unit
            ) {
                return first.compound || second.compound
                    ? first.conversions + second.conversions : []
            }
            // Component-wise interpolation consumes the leading endpoint-width
            // components of a proven wider weight, without changing its storage.
            guard let weight = componentExpression(ranges[2], tokens: tokens, unit: unit),
                  let weightWidth = floatVectorWidth(weight.type),
                  weightWidth > firstWidth,
                  let suffix = narrowingSuffix(from: weightWidth, to: firstWidth)
            else { return [] }
            return first.conversions + second.conversions + weight.conversions
                + [.init(range: weight.range, suffix: suffix)]
        })
        for conversion in conversions.sorted(by: { $0.range.count < $1.range.count }) {
            starts[conversion.range.lowerBound, default: 0] += 1
            ends[conversion.range.upperBound, default: []].append(conversion.suffix)
        }
    }

    static func componentExpression(
        _ range: Range<Int>,
        tokens: [SceneAuthoredShaderToken],
        unit: SceneAuthoredShaderSyntaxUnit,
        valueTypes: [String: SceneAuthoredShaderValueType]? = nil,
        permitsScalarVectorAddition: Bool = false,
        permitsVectorTruncation: Bool = false
    ) -> Expression? {
        guard !range.isEmpty else { return nil }
        return additiveExpression(range, tokens: tokens, unit: unit,
            valueTypes: valueTypes, permitsScalarVectorAddition: permitsScalarVectorAddition,
            permitsVectorTruncation: permitsVectorTruncation)
    }

    private static func additiveExpression(
        _ range: Range<Int>,
        tokens: [SceneAuthoredShaderToken],
        unit: SceneAuthoredShaderSyntaxUnit,
        valueTypes: [String: SceneAuthoredShaderValueType]? = nil,
        permitsScalarVectorAddition: Bool = false,
        permitsVectorTruncation: Bool = false
    ) -> Expression? {
        guard let ranges = split(range, operators: ["+", "-"], tokens: tokens),
              let first = ranges.first,
              let firstExpression = multiplicativeExpression(first, tokens: tokens, unit: unit,
                  valueTypes: valueTypes, permitsScalarVectorAddition: permitsScalarVectorAddition,
                  permitsVectorTruncation: permitsVectorTruncation)
        else { return nil }
        let expressions = [firstExpression] + ranges.dropFirst().compactMap {
            multiplicativeExpression($0, tokens: tokens, unit: unit,
                valueTypes: valueTypes, permitsScalarVectorAddition: permitsScalarVectorAddition,
                permitsVectorTruncation: permitsVectorTruncation)
        }
        guard expressions.count == ranges.count else { return nil }
        if expressions.count == 1 { return firstExpression }
        if expressions.allSatisfy({ [.float, .int, .uint].contains($0.type) }),
           let type = scalarArithmeticType(expressions.map(\.type)) {
            return .init(
                range: range, type: type,
                conversions: expressions.flatMap(\.conversions),
                compound: true, directlyNarrowable: false
            )
        }
        let types = Set(expressions.map(\.type))
        if permitsVectorTruncation,
           expressions.allSatisfy({ $0.type == .float || floatVectorWidth($0.type) != nil }),
           let width = expressions.compactMap({ floatVectorWidth($0.type) }).min(),
           width == 2 || Set(expressions.compactMap({ floatVectorWidth($0.type) })).count == 1 {
            let conversions = expressions.flatMap(\.conversions) + expressions.compactMap { value -> Conversion? in
                guard let source = floatVectorWidth(value.type), source > width,
                      let suffix = narrowingSuffix(from: source, to: width) else { return nil }
                return Conversion(range: value.range, suffix: suffix)
            }
            return .init(range: range, type: vectorType(width: width), conversions: conversions,
                compound: true, directlyNarrowable: false)
        }
        // Native floating vector +/- scalar arithmetic is needed to prove a
        // smoothstep input. Existing mix/pow width proofs keep their original
        // boundary; unlike multiplication this path never narrows a vector.
        if permitsScalarVectorAddition,
           let vector = types.first(where: { floatVectorWidth($0) != nil }),
           types.allSatisfy({ $0 == .float || $0 == vector }) {
            return .init(range: range, type: vector,
                conversions: expressions.flatMap(\.conversions),
                compound: true, directlyNarrowable: false)
        }
        guard types.count == 1, let type = types.first,
              type == .float || floatVectorWidth(type) != nil else { return nil }
        return .init(
            range: range,
            type: type,
            conversions: expressions.flatMap(\.conversions),
            compound: true,
            directlyNarrowable: false
        )
    }

    private static func multiplicativeExpression(
        _ range: Range<Int>,
        tokens: [SceneAuthoredShaderToken],
        unit: SceneAuthoredShaderSyntaxUnit,
        valueTypes: [String: SceneAuthoredShaderValueType]? = nil,
        permitsScalarVectorAddition: Bool = false,
        permitsVectorTruncation: Bool = false
    ) -> Expression? {
        guard let ranges = split(range, operators: ["*", "/", "%"], tokens: tokens),
              let first = ranges.first,
              let firstExpression = primaryExpression(first, tokens: tokens, unit: unit,
                  valueTypes: valueTypes, permitsScalarVectorAddition: permitsScalarVectorAddition,
                  permitsVectorTruncation: permitsVectorTruncation)
        else { return nil }
        let expressions = [firstExpression] + ranges.dropFirst().compactMap {
            primaryExpression($0, tokens: tokens, unit: unit,
                valueTypes: valueTypes, permitsScalarVectorAddition: permitsScalarVectorAddition,
                permitsVectorTruncation: permitsVectorTruncation)
        }
        guard expressions.count == ranges.count else { return nil }
        if expressions.count == 1 { return firstExpression }
        if expressions.allSatisfy({ [.float, .int, .uint].contains($0.type) }),
           let type = scalarArithmeticType(expressions.map(\.type)) {
            return .init(
                range: range,
                type: type,
                conversions: expressions.flatMap(\.conversions),
                compound: true,
                directlyNarrowable: false
            )
        }
        // Floating remainder admission is scalar-only. A vector remainder
        // must not inherit multiplication's vector narrowing semantics.
        guard !ranges.dropFirst().contains(where: {
            tokens[$0.lowerBound - 1].text == "%"
        }) else { return nil }
        let widths = expressions.compactMap { floatVectorWidth($0.type) }
        guard expressions.allSatisfy({ $0.type == .float || floatVectorWidth($0.type) != nil }),
              let width = widths.min(),
              expressions.allSatisfy({ expression in
                  guard let sourceWidth = floatVectorWidth(expression.type) else { return true }
                  return sourceWidth <= width || expression.directlyNarrowable
                      || (permitsVectorTruncation && width == 2)
              }) else { return nil }
        let type = vectorType(width: width)
        let conversions = expressions.flatMap(\.conversions) + expressions.compactMap {
            guard let sourceWidth = floatVectorWidth($0.type), sourceWidth > width,
                  let suffix = narrowingSuffix(from: sourceWidth, to: width)
            else { return nil }
            return Conversion(range: $0.range, suffix: suffix)
        }
        return .init(
            range: range,
            type: type,
            conversions: conversions,
            compound: true,
            directlyNarrowable: false
        )
    }

    private static func scalarArithmeticType(
        _ types: [SceneAuthoredShaderValueType]
    ) -> SceneAuthoredShaderValueType? {
        if types.contains(.float) { return .float }
        let distinct = Set(types)
        return distinct.count == 1 ? distinct.first : nil
    }

    private static func primaryExpression(
        _ sourceRange: Range<Int>,
        tokens: [SceneAuthoredShaderToken],
        unit: SceneAuthoredShaderSyntaxUnit,
        valueTypes: [String: SceneAuthoredShaderValueType]? = nil,
        permitsScalarVectorAddition: Bool = false,
        permitsVectorTruncation: Bool = false
    ) -> Expression? {
        var range = sourceRange
        while range.count > 1, ["+", "-"].contains(tokens[range.lowerBound].text) {
            range = (range.lowerBound + 1)..<range.upperBound
        }
        if range.count >= 2, tokens[range.lowerBound].text == "(",
           tokens[range.upperBound - 1].text == ")",
           SceneAuthoredShaderTokenScanner.matchingParenthesis(tokens: tokens, opening: range.lowerBound) == range.upperBound - 1,
           let nested = additiveExpression(
               (range.lowerBound + 1)..<(range.upperBound - 1),
               tokens: tokens,
               unit: unit,
               valueTypes: valueTypes,
               permitsScalarVectorAddition: permitsScalarVectorAddition,
               permitsVectorTruncation: permitsVectorTruncation
           ) {
            return .init(
                range: sourceRange,
                type: nested.type,
                conversions: nested.conversions,
                compound: true,
                directlyNarrowable: false
            )
        }
        if range.count == 1, tokens[range.lowerBound].kind == .number {
            return .init(
                range: sourceRange,
                type: permitsVectorTruncation
                    && numericLiteralType(tokens[range.lowerBound].text) == .int
                    ? .float : numericLiteralType(tokens[range.lowerBound].text),
                conversions: [],
                compound: false,
                directlyNarrowable: false
            )
        }
        if permitsVectorTruncation,
           let constructor = floatingConstructor(range, tokens: tokens, unit: unit) {
            return .init(range: sourceRange, type: constructor.type,
                conversions: constructor.conversions, compound: false, directlyNarrowable: true)
        }
        if !permitsVectorTruncation, let builtIn = floatBuiltInExpression(
            sourceRange,
            tokens: tokens,
            unit: unit,
            valueTypes: valueTypes,
            permitsScalarVectorAddition: permitsScalarVectorAddition
        ) {
            return builtIn
        }
        guard tokens[range.lowerBound].kind == .identifier else { return nil }
        let name = tokens[range.lowerBound].text
        let declared: SceneAuthoredShaderValueType?
        if let valueTypes {
            declared = valueTypes[name]
        } else {
            declared = SceneAuthoredShaderGlobalReferenceAnalyzer.valueType(
                    at: range.lowerBound, tokens: tokens, in: unit
                )
        }
        guard let declared else { return nil }
        if range.count == 1 {
            return .init(
                range: sourceRange,
                type: declared,
                conversions: [],
                compound: false,
                directlyNarrowable: true
            )
        }
        guard range.count == 3, tokens[range.lowerBound + 1].text == ".",
              tokens[range.lowerBound + 2].kind == .identifier,
              let type = swizzleType(
                  tokens[range.lowerBound + 2].text,
                  base: declared
              ) else { return nil }
        return .init(
            range: sourceRange,
            type: type,
            conversions: [],
            compound: false,
            directlyNarrowable: true
        )
    }

    private static func floatingConstructor(
        _ range: Range<Int>, tokens: [SceneAuthoredShaderToken], unit: SceneAuthoredShaderSyntaxUnit
    ) -> Expression? {
        guard range.count >= 4, tokens[range.lowerBound + 1].text == "(",
              SceneAuthoredShaderTokenScanner.matchingParenthesis(tokens: tokens, opening: range.lowerBound + 1) == range.upperBound - 1,
              !unit.functions.contains(where: { $0.name == tokens[range.lowerBound].text }),
              let arguments = argumentRanges(opening: range.lowerBound + 1, closing: range.upperBound - 1, tokens: tokens),
              !arguments.isEmpty else { return nil }
        let name = tokens[range.lowerBound].text
        let type: SceneAuthoredShaderValueType?
        switch name {
        case "CAST2": type = .float2
        case "CAST3": type = .float3
        case "CAST4": type = .float4
        default: type = SceneAuthoredShaderValueType(authoredName: name)
        }
        guard let type, type == .float || floatVectorWidth(type) != nil else { return nil }
        // The explicit constructor fixes its result type. Preserve proven
        // child conversions, while the compiler validates other arguments.
        let values = arguments.compactMap {
            componentExpression($0, tokens: tokens, unit: unit, permitsVectorTruncation: true)
        }
        var conversions = values.flatMap(\.conversions)
        if arguments.count == 1, let value = values.first,
           let sourceWidth = floatVectorWidth(value.type),
           let targetWidth = floatVectorWidth(type), sourceWidth > targetWidth,
           let suffix = narrowingSuffix(from: sourceWidth, to: targetWidth) {
            // Complete the argument at its own width before the constructor
            // consumes its leading components.
            conversions.append(.init(range: arguments[0], suffix: suffix))
        }
        return .init(range: range, type: type, conversions: conversions,
            compound: false, directlyNarrowable: true)
    }

    /// Prove floating built-in result types from their operands, excluding
    /// authored overloads. Unary calls preserve shape; multi-argument calls
    /// here are scalar, with integer literals promoted by floating operands.
    private static func floatBuiltInExpression(
        _ range: Range<Int>,
        tokens: [SceneAuthoredShaderToken],
        unit: SceneAuthoredShaderSyntaxUnit,
        valueTypes: [String: SceneAuthoredShaderValueType]? = nil,
        permitsScalarVectorAddition: Bool = false,
        permitsVectorTruncation: Bool = false
    ) -> Expression? {
        guard range.count >= 4,
              tokens[range.lowerBound].kind == .identifier else { return nil }
        let name = tokens[range.lowerBound].text
        let expectedCount: Int
        switch name {
        case "abs", "sin", "saturate": expectedCount = 1
        case "step", "pow": expectedCount = 2
        case "smoothstep": expectedCount = 3
        default: return nil
        }
        guard !unit.functions.contains(where: { $0.name == name }),
              tokens[range.lowerBound + 1].text == "(",
              SceneAuthoredShaderTokenScanner.matchingParenthesis(
                  tokens: tokens,
                  opening: range.lowerBound + 1
              ) == range.upperBound - 1,
              let ranges = argumentRanges(
                  opening: range.lowerBound + 1,
                  closing: range.upperBound - 1,
                  tokens: tokens
              ), ranges.count == expectedCount else { return nil }
        let arguments = ranges.compactMap {
            componentExpression($0, tokens: tokens, unit: unit,
                valueTypes: valueTypes, permitsScalarVectorAddition: permitsScalarVectorAddition,
                permitsVectorTruncation: permitsVectorTruncation)
        }
        if expectedCount == 1, arguments.count == 1,
           let argument = arguments.first,
           argument.type == .float || floatVectorWidth(argument.type) != nil {
            return .init(
                range: range,
                type: argument.type,
                conversions: argument.conversions,
                compound: true,
                directlyNarrowable: false
            )
        }
        guard arguments.count == ranges.count,
              arguments.allSatisfy({ [.float, .int].contains($0.type) }),
              arguments.contains(where: { $0.type == .float }) else { return nil }
        return .init(
            range: range,
            type: .float,
            conversions: arguments.flatMap(\.conversions),
            compound: true,
            directlyNarrowable: false
        )
    }

    private static func split(
        _ range: Range<Int>,
        operators: Set<String>,
        tokens: [SceneAuthoredShaderToken]
    ) -> [Range<Int>]? {
        var result: [Range<Int>] = []
        var start = range.lowerBound
        var depth = 0
        for index in range {
            if ["(", "["].contains(tokens[index].text) { depth += 1 }
            if [")", "]"].contains(tokens[index].text) { depth -= 1 }
            guard depth >= 0 else { return nil }
            guard depth == 0, operators.contains(tokens[index].text), index > start else { continue }
            result.append(start..<index)
            start = (index + 1)
        }
        guard depth == 0, start < range.upperBound else { return nil }
        result.append(start..<range.upperBound)
        return result
    }

    private static func vectorType(width: Int) -> SceneAuthoredShaderValueType {
        [.float2, .float3, .float4][width - 2]
    }

    private static func validWeight(
        _ range: Range<Int>,
        width: Int,
        before limit: Int,
        tokens: [SceneAuthoredShaderToken],
        unit: SceneAuthoredShaderSyntaxUnit
    ) -> Bool {
        if let type = standaloneType(
            range, before: limit, tokens: tokens, unit: unit
        ) {
            return type == .float || floatVectorWidth(type) == width
        }
        // A source-proven scalar built-in expression is a valid scalar mix
        // weight. Vector expressions and authored overloads stay closed.
        return componentExpression(range, tokens: tokens, unit: unit)?.type == .float
    }

    private static func standaloneType(
        _ range: Range<Int>,
        before limit: Int,
        tokens: [SceneAuthoredShaderToken],
        unit: SceneAuthoredShaderSyntaxUnit
    ) -> SceneAuthoredShaderValueType? {
        if range.count == 1, tokens[range.lowerBound].kind == .number {
            return numericLiteralType(tokens[range.lowerBound].text)
        }
        guard tokens[range.lowerBound].kind == .identifier,
              let declared = SceneAuthoredShaderGlobalReferenceAnalyzer.valueType(
                    at: range.lowerBound, tokens: tokens, in: unit
                ) else { return nil }
        if range.count == 1 { return declared }
        guard range.count == 3,
              tokens[range.lowerBound + 1].text == ".",
              tokens[range.lowerBound + 2].kind == .identifier else { return nil }
        return swizzleType(
            tokens[range.lowerBound + 2].text,
            base: declared
        )
    }

    static func argumentRanges(
        opening: Int,
        closing: Int,
        tokens: [SceneAuthoredShaderToken]
    ) -> [Range<Int>]? {
        var ranges: [Range<Int>] = []
        var start = opening + 1
        var depth = 0
        for index in (opening + 1)...closing {
            let isEnd = index == closing
            if !isEnd, ["(", "["].contains(tokens[index].text) { depth += 1 }
            if !isEnd, [")", "]"].contains(tokens[index].text) { depth -= 1 }
            guard depth >= 0 else { return nil }
            guard isEnd || (depth == 0 && tokens[index].text == ",") else { continue }
            ranges.append(start..<index)
            start = index + 1
        }
        return ranges
    }

    private static func enclosingCallOpening(
        for index: Int,
        in tokens: [SceneAuthoredShaderToken]
    ) -> Int? {
        var depth = 0
        for cursor in stride(from: index - 1, through: 0, by: -1) {
            if tokens[cursor].text == ")" { depth += 1 }
            if tokens[cursor].text == "(" {
                if depth == 0 { return cursor }
                depth -= 1
            }
            if depth == 0, [";", "{", "}"].contains(tokens[cursor].text) { return nil }
        }
        return nil
    }

    private static func numericLiteralType(
        _ value: String
    ) -> SceneAuthoredShaderValueType {
        if value.last.map({ $0 == "u" || $0 == "U" }) == true {
            return .uint
        }
        if value.contains(".") || value.contains("e") || value.contains("E")
            || value.last.map({ $0 == "f" || $0 == "F" }) == true {
            return .float
        }
        return .int
    }

    private static func swizzleType(
        _ value: String,
        base: SceneAuthoredShaderValueType
    ) -> SceneAuthoredShaderValueType? {
        guard (1...4).contains(value.count),
              value.allSatisfy({ "xyzwrgba".contains($0) }) else { return nil }
        switch base {
        case .float2, .float3, .float4:
            return [.float, .float2, .float3, .float4][value.count - 1]
        case .int2, .int3, .int4:
            return [.int, .int2, .int3, .int4][value.count - 1]
        case .uint2, .uint3, .uint4:
            return [.uint, .uint2, .uint3, .uint4][value.count - 1]
        default:
            return nil
        }
    }

    static func floatVectorWidth(_ type: SceneAuthoredShaderValueType) -> Int? {
        switch type {
        case .float2: 2
        case .float3: 3
        case .float4: 4
        default: nil
        }
    }

    private static func narrowingSuffix(from source: Int, to target: Int) -> String? {
        switch (source, target) {
        case (4, 3): "xyz"
        case (4, 2), (3, 2): "xy"
        default: nil
        }
    }
}
