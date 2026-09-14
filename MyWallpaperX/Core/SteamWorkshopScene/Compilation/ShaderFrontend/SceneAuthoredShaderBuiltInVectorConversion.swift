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
            rewriteZeroLowerBoundBroadcasts(
                rewriteScalarPowBroadcasts(
                    rewriteScalarMixBroadcasts(source, stage: stage),
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
              let closing = matchingParenthesis(tokens: tokens, opening: opening),
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
    /// endpoint of `mix`/`lerp`. Vulkan GLSL requires both endpoints to have
    /// the same shape. Canonicalize only simple, statically typed endpoints;
    /// compound expressions and user-defined overloads remain untouched and
    /// therefore retain the normal compiler rejection boundary.
    static func rewriteScalarMixBroadcasts(
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
        func tokenOffset(_ index: Int, afterToken: Bool) -> Int? {
            guard unit.tokens.indices.contains(index) else { return nil }
            let token = unit.tokens[index]
            guard token.line > 0, token.line <= lineStarts.count else { return nil }
            return lineStarts[token.line - 1] + token.column - 1
                + (afterToken ? token.text.unicodeScalars.count : 0)
        }

        var insertions: [(offset: Int, text: String)] = []
        for index in unit.tokens.indices {
            guard ["mix", "lerp"].contains(unit.tokens[index].text),
                  !unit.functions.contains(where: {
                      $0.name == unit.tokens[index].text
                  }), index + 1 < unit.tokens.count,
                  unit.tokens[index + 1].text == "(",
                  let closing = matchingParenthesis(
                      tokens: unit.tokens,
                      opening: index + 1
                  ),
                  let arguments = argumentRanges(
                      opening: index + 1,
                      closing: closing,
                      tokens: unit.tokens
                  ), arguments.count == 3,
                  let first = standaloneType(
                      arguments[0], before: index,
                      tokens: unit.tokens, unit: unit
                  ),
                  let second = standaloneType(
                      arguments[1], before: index,
                      tokens: unit.tokens, unit: unit
                  ) else { continue }
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

    /// Stock authored shaders use `max(0, float-vector)` as an exact
    /// component-wise nonnegative bound. Vulkan GLSL has no scalar-first
    /// overload and will not promote the integer zero. Preserve that bounded
    /// authored form without opening other implicit numeric conversions.
    private static func rewriteZeroLowerBoundBroadcasts(
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
        func tokenOffset(_ index: Int, afterToken: Bool) -> Int? {
            guard unit.tokens.indices.contains(index) else { return nil }
            let token = unit.tokens[index]
            guard token.line > 0, token.line <= lineStarts.count else { return nil }
            return lineStarts[token.line - 1] + token.column - 1
                + (afterToken ? token.text.unicodeScalars.count : 0)
        }
        var replacements: [(start: Int, end: Int, text: String)] = []
        for index in unit.tokens.indices {
            guard unit.tokens[index].text == "max",
                  !unit.functions.contains(where: { $0.name == "max" }),
                  index + 1 < unit.tokens.count,
                  unit.tokens[index + 1].text == "(",
                  let closing = matchingParenthesis(
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
                  unit.tokens[arguments[0].lowerBound].text == "0",
                  let second = standaloneType(
                      arguments[1], before: index,
                      tokens: unit.tokens, unit: unit
                  ), let vectorWidth = floatVectorWidth(second) else { continue }
            guard let start = tokenOffset(
                      arguments[0].lowerBound,
                      afterToken: false
                  ),
                  let end = tokenOffset(
                      arguments[0].upperBound - 1,
                      afterToken: true
                  ) else { continue }
            replacements.append((start, end, "vec\(vectorWidth)(0.0)"))
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
    /// ambiguous. Promote only a single decimal integer literal whose peer is
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
        func tokenOffset(_ index: Int, afterToken: Bool) -> Int? {
            guard unit.tokens.indices.contains(index) else { return nil }
            let token = unit.tokens[index]
            guard token.line > 0, token.line <= lineStarts.count else {
                return nil
            }
            return lineStarts[token.line - 1] + token.column - 1
                + (afterToken ? token.text.unicodeScalars.count : 0)
        }
        var insertions: [Int] = []
        for index in unit.tokens.indices {
            let name = unit.tokens[index].text
            guard ["min", "max"].contains(name),
                  !unit.functions.contains(where: { $0.name == name }),
                  index + 1 < unit.tokens.count,
                  unit.tokens[index + 1].text == "(",
                  let closing = matchingParenthesis(
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
            insertions.append(end)
        }
        guard !insertions.isEmpty else { return normalized }

        var result = normalized
        for offset in insertions.sorted(by: >) {
            guard offset <= result.unicodeScalars.count else {
                return normalized
            }
            let scalarIndex = result.unicodeScalars.index(
                result.unicodeScalars.startIndex,
                offsetBy: offset
            )
            guard let stringIndex = String.Index(
                scalarIndex,
                within: result
            ) else { return normalized }
            result.insert(contentsOf: ".0", at: stringIndex)
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
                  let closing = matchingParenthesis(tokens: tokens, opening: index),
                  let ranges = argumentRanges(opening: index, closing: closing, tokens: tokens),
                  ranges.count == 3,
                  let first = componentExpression(ranges[0], tokens: tokens, unit: unit),
                  let second = componentExpression(ranges[1], tokens: tokens, unit: unit),
                  first.compound || second.compound,
                  let firstWidth = floatVectorWidth(first.type),
                  firstWidth == floatVectorWidth(second.type),
                  validWeight(
                      ranges[2], width: firstWidth, before: index,
                      tokens: tokens, unit: unit
                  ) else { return [] }
            return first.conversions + second.conversions
        })
        for conversion in conversions {
            starts[conversion.range.lowerBound, default: 0] += 1
            ends[conversion.range.upperBound, default: []].append(conversion.suffix)
        }
    }

    static func componentExpression(
        _ range: Range<Int>,
        tokens: [SceneAuthoredShaderToken],
        unit: SceneAuthoredShaderSyntaxUnit
    ) -> Expression? {
        guard !range.isEmpty else { return nil }
        return additiveExpression(range, tokens: tokens, unit: unit)
    }

    private static func additiveExpression(
        _ range: Range<Int>,
        tokens: [SceneAuthoredShaderToken],
        unit: SceneAuthoredShaderSyntaxUnit
    ) -> Expression? {
        guard let ranges = split(range, operators: ["+", "-"], tokens: tokens),
              let first = ranges.first,
              let firstExpression = multiplicativeExpression(first, tokens: tokens, unit: unit)
        else { return nil }
        let expressions = [firstExpression] + ranges.dropFirst().compactMap {
            multiplicativeExpression($0, tokens: tokens, unit: unit)
        }
        guard expressions.count == ranges.count else { return nil }
        if expressions.count == 1 { return firstExpression }
        let types = Set(expressions.map(\.type))
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
        unit: SceneAuthoredShaderSyntaxUnit
    ) -> Expression? {
        guard let ranges = split(range, operators: ["*", "/"], tokens: tokens),
              let first = ranges.first,
              let firstExpression = primaryExpression(first, tokens: tokens, unit: unit)
        else { return nil }
        let expressions = [firstExpression] + ranges.dropFirst().compactMap {
            primaryExpression($0, tokens: tokens, unit: unit)
        }
        guard expressions.count == ranges.count else { return nil }
        if expressions.count == 1 { return firstExpression }
        if expressions.allSatisfy({ $0.type == .float }) {
            return .init(
                range: range,
                type: .float,
                conversions: expressions.flatMap(\.conversions),
                compound: true,
                directlyNarrowable: false
            )
        }
        let widths = expressions.compactMap { floatVectorWidth($0.type) }
        guard expressions.allSatisfy({ $0.type == .float || floatVectorWidth($0.type) != nil }),
              let width = widths.min(),
              expressions.allSatisfy({ expression in
                  guard let sourceWidth = floatVectorWidth(expression.type) else { return true }
                  return sourceWidth <= width || expression.directlyNarrowable
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

    private static func primaryExpression(
        _ sourceRange: Range<Int>,
        tokens: [SceneAuthoredShaderToken],
        unit: SceneAuthoredShaderSyntaxUnit
    ) -> Expression? {
        var range = sourceRange
        while range.count > 1, ["+", "-"].contains(tokens[range.lowerBound].text) {
            range = (range.lowerBound + 1)..<range.upperBound
        }
        if range.count >= 2, tokens[range.lowerBound].text == "(",
           tokens[range.upperBound - 1].text == ")",
           matchingParenthesis(tokens: tokens, opening: range.lowerBound) == range.upperBound - 1,
           let nested = additiveExpression(
               (range.lowerBound + 1)..<(range.upperBound - 1),
               tokens: tokens,
               unit: unit
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
                type: numericLiteralType(tokens[range.lowerBound].text),
                conversions: [],
                compound: false,
                directlyNarrowable: false
            )
        }
        if let builtIn = scalarFloatBuiltInExpression(
            sourceRange,
            tokens: tokens,
            unit: unit
        ) {
            return builtIn
        }
        guard tokens[range.lowerBound].kind == .identifier,
              let declared = declaredType(
                  tokens[range.lowerBound].text,
                  before: range.lowerBound,
                  tokens: tokens,
                  unit: unit
              ) else { return nil }
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

    /// `step` and `smoothstep` return the scalar floating shape of their
    /// scalar authored operands. Prove only that narrow built-in surface so a
    /// surrounding `min`/`max` can select its floating overload. User
    /// overloads and vector/unknown arguments remain untouched.
    private static func scalarFloatBuiltInExpression(
        _ range: Range<Int>,
        tokens: [SceneAuthoredShaderToken],
        unit: SceneAuthoredShaderSyntaxUnit
    ) -> Expression? {
        guard range.count >= 4,
              tokens[range.lowerBound].kind == .identifier else { return nil }
        let name = tokens[range.lowerBound].text
        let expectedCount: Int
        switch name {
        case "step": expectedCount = 2
        case "smoothstep": expectedCount = 3
        default: return nil
        }
        guard !unit.functions.contains(where: { $0.name == name }),
              tokens[range.lowerBound + 1].text == "(",
              matchingParenthesis(
                  tokens: tokens,
                  opening: range.lowerBound + 1
              ) == range.upperBound - 1,
              let ranges = argumentRanges(
                  opening: range.lowerBound + 1,
                  closing: range.upperBound - 1,
                  tokens: tokens
              ), ranges.count == expectedCount else { return nil }
        let arguments = ranges.compactMap {
            componentExpression($0, tokens: tokens, unit: unit)
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
        guard let type = standaloneType(
            range, before: limit, tokens: tokens, unit: unit
        ) else { return false }
        return type == .float || floatVectorWidth(type) == width
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
              let declared = declaredType(
                  tokens[range.lowerBound].text,
                  before: limit,
                  tokens: tokens,
                  unit: unit
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

    private static func declaredType(
        _ name: String,
        before limit: Int,
        tokens: [SceneAuthoredShaderToken],
        unit: SceneAuthoredShaderSyntaxUnit
    ) -> SceneAuthoredShaderValueType? {
        var types = Set(unit.declarations.compactMap {
            $0.name == name
                ? SceneAuthoredShaderValueType(authoredName: $0.typeName) : nil
        })
        for index in 0..<limit where index + 1 < tokens.count {
            guard tokens[index + 1].text == name,
                  let type = SceneAuthoredShaderValueType(
                      authoredName: tokens[index].text
                  ) else { continue }
            types.insert(type)
        }
        return types.count == 1 ? types.first : nil
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

    static func matchingParenthesis(
        tokens: [SceneAuthoredShaderToken],
        opening: Int
    ) -> Int? {
        var depth = 0
        for index in opening..<tokens.count {
            if tokens[index].text == "(" { depth += 1 }
            if tokens[index].text == ")" {
                depth -= 1
                if depth == 0 { return index }
            }
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
