import Foundation

nonisolated enum SceneAuthoredShaderBuiltInVectorConversion {
    struct Conversion: Hashable {
        enum Operation: Hashable {
            case narrow(String)
            case broadcast(Int)
            case floatingLiteral
            case scalarDot
        }

        let range: Range<Int>
        let operation: Operation

        init(range: Range<Int>, operation: Operation) {
            self.range = range
            self.operation = operation
        }

        init(range: Range<Int>, suffix: String) {
            self.init(range: range, operation: .narrow(suffix))
        }

        var narrowingSuffix: String? {
            guard case let .narrow(suffix) = operation else { return nil }
            return suffix
        }
    }

    struct Expression {
        let range: Range<Int>
        let type: SceneAuthoredShaderValueType
        let conversions: [Conversion]
        let compound: Bool
        let directlyNarrowable: Bool
    }

    private struct Wrapping: Hashable {
        let range: Range<Int>
        let prefix: String
        let suffix: String
    }

    static func rewriteIntrinsicArguments(
        _ source: String,
        stage: SceneShaderContract.StageKind
    ) -> String {
        let normalized = source.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let analysisSource = normalized.components(separatedBy: "\n").map {
            $0.trimmingCharacters(in: .whitespaces).hasPrefix("#version") ? "" : $0
        }.joined(separator: "\n")
        let analysis = SceneAuthoredShaderSyntaxAnalyzer.analyzeForTypeConversions(
            lexerOutput: SceneAuthoredShaderLexer.lex(source: analysisSource, stage: stage),
            stage: stage
        )
        guard analysis.diagnostics.isEmpty, let unit = analysis.unit else { return normalized }
        let conversions = Set(intrinsicExpressions(in: unit.tokens, unit: unit).flatMap(\.conversions))
        guard !conversions.isEmpty else { return normalized }
        return applying(conversions, to: normalized, tokens: unit.tokens)
    }

    static func intrinsicExpressions(
        in tokens: [SceneAuthoredShaderToken], unit: SceneAuthoredShaderSyntaxUnit
    ) -> [Expression] {
        return tokens.indices.compactMap { index in
            guard intrinsicArgumentCount(tokens[index].text) != nil,
                  index + 1 < tokens.count, tokens[index + 1].text == "(",
                  let closing = SceneAuthoredShaderTokenScanner.matchingParenthesis(
                    tokens: tokens, opening: index + 1) else { return nil }
            return floatBuiltInExpression(index..<(closing + 1), tokens: tokens, unit: unit,
                permitsScalarVectorAddition: true, permitsVectorTruncation: true)
        }
    }

    private static func applying(
        _ conversions: Set<Conversion>, to source: String,
        tokens: [SceneAuthoredShaderToken]
    ) -> String {
        let scalars = Array(source.unicodeScalars)
        var lineStarts = [0]
        for (index, scalar) in scalars.enumerated() where scalar == "\n" {
            lineStarts.append(index + 1)
        }
        func offset(_ index: Int, after: Bool = false) -> Int {
            let token = tokens[index]
            return lineStarts[token.line - 1] + token.column - 1
                + (after ? token.text.unicodeScalars.count : 0)
        }
        var wrappings: Set<Wrapping> = []
        var replacements: [Int: (end: Int, text: String)] = [:]
        for conversion in conversions {
            let range = conversion.range
            switch conversion.operation {
            case let .narrow(suffix):
                wrappings.insert(.init(range: range, prefix: "(", suffix: ").\(suffix)"))
            case let .broadcast(width):
                wrappings.insert(.init(range: range, prefix: "vec\(width)(", suffix: ")"))
            case .floatingLiteral:
                let literal = tokens[range.lowerBound].text
                // 010 must remain eight rather than becoming the decimal 10.0.
                if literal.count > 1 && literal.first == "0" {
                    wrappings.insert(.init(range: range, prefix: "float(", suffix: ")"))
                } else {
                    replacements[offset(range.lowerBound)] = (
                        offset(range.upperBound - 1, after: true), literal + ".0")
                }
            case .scalarDot:
                guard let arguments = argumentRanges(opening: range.lowerBound + 1,
                    closing: range.upperBound - 1, tokens: tokens) else { continue }
                replacements[offset(range.lowerBound)] = (offset(range.lowerBound, after: true), "")
                let comma = arguments[0].upperBound
                replacements[offset(comma)] = (offset(comma, after: true), " * ")
                for argument in arguments {
                    wrappings.insert(.init(range: argument, prefix: "(", suffix: ")"))
                }
            }
        }
        var openings: [Int: [(width: Int, text: String)]] = [:]
        var endings: [Int: [(width: Int, text: String)]] = [:]
        for wrapping in wrappings {
            openings[offset(wrapping.range.lowerBound), default: []]
                .append((wrapping.range.count, wrapping.prefix))
            endings[offset(wrapping.range.upperBound - 1, after: true), default: []]
                .append((wrapping.range.count, wrapping.suffix))
        }
        let positions = Set(openings.keys).union(endings.keys).union(replacements.keys).sorted()
        var result = String.UnicodeScalarView()
        var cursor = 0
        for position in positions {
            guard position >= cursor, position <= scalars.count else { return source }
            result.append(contentsOf: scalars[cursor..<position])
            for ending in (endings[position] ?? []).sorted(by: {
                $0.width == $1.width ? $0.text < $1.text : $0.width < $1.width
            }) { result.append(contentsOf: ending.text.unicodeScalars) }
            for opening in (openings[position] ?? []).sorted(by: {
                $0.width == $1.width ? $0.text > $1.text : $0.width > $1.width
            }) { result.append(contentsOf: opening.text.unicodeScalars) }
            if let replacement = replacements[position] {
                guard replacement.end <= scalars.count else { return source }
                result.append(contentsOf: replacement.text.unicodeScalars)
                cursor = replacement.end
            } else { cursor = position }
        }
        result.append(contentsOf: scalars[cursor...])
        return String(result)
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
           let width = expressions.compactMap({ floatVectorWidth($0.type) }).min() {
            let conversions = expressions.flatMap(\.conversions) + expressions.compactMap { value -> Conversion? in
                guard let source = floatVectorWidth(value.type), source > width,
                      let suffix = narrowingSuffix(from: source, to: width) else { return nil }
                return Conversion(range: value.range, suffix: suffix)
            }
            return .init(range: range, type: vectorType(width: width), conversions: conversions,
                compound: true, directlyNarrowable: false)
        }
        // Queries that permit scalar addition alone retain the vector width.
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
                      || permitsVectorTruncation
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
        if range.count > 2, tokens[range.upperBound - 2].text == ".",
           tokens[range.upperBound - 1].kind == .identifier,
           let base = primaryExpression(range.lowerBound..<(range.upperBound - 2),
                tokens: tokens, unit: unit, valueTypes: valueTypes,
                permitsScalarVectorAddition: permitsScalarVectorAddition,
                permitsVectorTruncation: permitsVectorTruncation),
           let type = swizzleType(tokens[range.upperBound - 1].text, base: base.type) {
            return .init(range: sourceRange, type: type, conversions: base.conversions,
                compound: base.compound, directlyNarrowable: true)
        }
        if range.count >= 2, tokens[range.lowerBound].text == "(",
           SceneAuthoredShaderTokenScanner.matchingParenthesis(tokens: tokens,
                opening: range.lowerBound) == range.upperBound - 1,
           let nested = additiveExpression((range.lowerBound + 1)..<(range.upperBound - 1),
                tokens: tokens, unit: unit, valueTypes: valueTypes,
                permitsScalarVectorAddition: permitsScalarVectorAddition,
                permitsVectorTruncation: permitsVectorTruncation) {
            return .init(range: sourceRange, type: nested.type, conversions: nested.conversions,
                compound: true, directlyNarrowable: false)
        }
        if range.count == 1, tokens[range.lowerBound].kind == .number {
            return .init(range: sourceRange,
                type: permitsVectorTruncation && numericLiteralType(tokens[range.lowerBound].text) == .int
                    ? .float : numericLiteralType(tokens[range.lowerBound].text),
                conversions: [], compound: false, directlyNarrowable: false)
        }
        if let constructor = floatingConstructor(range, tokens: tokens, unit: unit,
            valueTypes: valueTypes, permitsScalarVectorAddition: permitsScalarVectorAddition,
            permitsVectorTruncation: permitsVectorTruncation) {
            return .init(range: sourceRange, type: constructor.type,
                conversions: constructor.conversions, compound: false, directlyNarrowable: true)
        }
        if let builtIn = floatBuiltInExpression(range, tokens: tokens, unit: unit,
            valueTypes: valueTypes, permitsScalarVectorAddition: permitsScalarVectorAddition,
            permitsVectorTruncation: permitsVectorTruncation) { return builtIn }
        guard tokens[range.lowerBound].kind == .identifier else { return nil }
        let name = tokens[range.lowerBound].text
        if range.count >= 3, tokens[range.lowerBound + 1].text == "(",
           SceneAuthoredShaderTokenScanner.matchingParenthesis(tokens: tokens,
                opening: range.lowerBound + 1) == range.upperBound - 1,
           let function = SceneAuthoredShaderFunctionSemantics.uniqueUnshadowedSourceFunction(
                named: name, tokens: unit.tokens, functions: unit.functions),
           let type = SceneAuthoredShaderValueType(authoredName: function.returnType) {
            // Only the return declaration is borrowed. The compiler owns the
            // parameters and body, including every out/inout side effect.
            return .init(range: sourceRange, type: type, conversions: [],
                compound: true, directlyNarrowable: false)
        }
        guard range.count == 1 else { return nil }
        let declared: SceneAuthoredShaderValueType?
        if let valueTypes { declared = valueTypes[name] }
        else {
            declared = SceneAuthoredShaderGlobalReferenceAnalyzer.valueType(
                at: range.lowerBound, tokens: tokens, in: unit)
        }
        guard let type = declared else { return nil }
        return .init(range: sourceRange, type: type, conversions: [],
            compound: false, directlyNarrowable: true)
    }

    private static func floatingConstructor(
        _ range: Range<Int>, tokens: [SceneAuthoredShaderToken], unit: SceneAuthoredShaderSyntaxUnit,
        valueTypes: [String: SceneAuthoredShaderValueType]?,
        permitsScalarVectorAddition: Bool, permitsVectorTruncation: Bool
    ) -> Expression? {
        guard range.count >= 4, tokens[range.lowerBound + 1].text == "(",
              SceneAuthoredShaderTokenScanner.matchingParenthesis(tokens: tokens,
                opening: range.lowerBound + 1) == range.upperBound - 1,
              unshadowedCall(at: range.lowerBound, tokens: tokens, unit: unit),
              let arguments = argumentRanges(opening: range.lowerBound + 1,
                closing: range.upperBound - 1, tokens: tokens), !arguments.isEmpty else { return nil }
        let type: SceneAuthoredShaderValueType?
        switch tokens[range.lowerBound].text {
        case "CAST2": type = .float2
        case "CAST3": type = .float3
        case "CAST4": type = .float4
        default: type = SceneAuthoredShaderValueType(authoredName: tokens[range.lowerBound].text)
        }
        guard let type, type == .float || floatVectorWidth(type) != nil else { return nil }
        // A constructor fixes its result type even when a child remains
        // compiler-owned. Preserve conversions only for known children.
        let values = arguments.compactMap {
            componentExpression($0, tokens: tokens, unit: unit, valueTypes: valueTypes,
                permitsScalarVectorAddition: permitsScalarVectorAddition,
                permitsVectorTruncation: permitsVectorTruncation)
        }
        var conversions = values.flatMap(\.conversions)
        if arguments.count == 1, let value = values.first,
           let sourceWidth = floatVectorWidth(value.type),
           let targetWidth = floatVectorWidth(type), sourceWidth > targetWidth,
           let suffix = narrowingSuffix(from: sourceWidth, to: targetWidth) {
            conversions.append(.init(range: arguments[0], suffix: suffix))
        }
        return .init(range: range, type: type, conversions: conversions,
            compound: false, directlyNarrowable: true)
    }

    private static func intrinsicArgumentCount(_ name: String) -> Int? {
        switch name {
        case "abs", "sin", "saturate", "normalize": 1
        case "dot", "pow", "min", "max", "step": 2
        case "mix", "lerp", "clamp", "smoothstep": 3
        default: nil
        }
    }

    static func unshadowedCall(
        at index: Int, tokens: [SceneAuthoredShaderToken], unit: SceneAuthoredShaderSyntaxUnit
    ) -> Bool {
        let token = tokens[index]
        let name = token.text
        let structureNames = SceneAuthoredShaderGlobalReferenceAnalyzer.structureTypeNames(in: unit)
        guard (index == 0 || tokens[index - 1].text != "."),
              !unit.functions.contains(where: { $0.name == name }), !structureNames.contains(name),
              SceneAuthoredShaderGlobalReferenceAnalyzer.valueType(of: token, in: unit) == nil
        else { return false }
        let references = SceneAuthoredShaderGlobalReferenceAnalyzer.referenceIndices(name, in: unit)
        // A local array or unknown value shadow also suppresses a global call
        // reference. A parameter in another function cannot suppress this one.
        return references.contains(where: { unit.tokens[$0] == token })
            && !references.contains(where: { reference in
                // Prototypes have no function body in SyntaxUnit. Preserve
                // their declared name without collecting unrelated value names.
                guard reference > 0, reference + 1 < unit.tokens.count,
                      unit.tokens[reference + 1].text == "(" else { return false }
                let returnType = unit.tokens[reference - 1].text
                return returnType == "void" || structureNames.contains(returnType)
                    || SceneAuthoredShaderValueType(authoredName: returnType) != nil
            })
    }

    private static func floatBuiltInExpression(
        _ range: Range<Int>, tokens: [SceneAuthoredShaderToken], unit: SceneAuthoredShaderSyntaxUnit,
        valueTypes: [String: SceneAuthoredShaderValueType]? = nil,
        permitsScalarVectorAddition: Bool = false, permitsVectorTruncation: Bool = false
    ) -> Expression? {
        guard range.count >= 4,
              let count = intrinsicArgumentCount(tokens[range.lowerBound].text),
              unshadowedCall(at: range.lowerBound, tokens: tokens, unit: unit),
              tokens[range.lowerBound + 1].text == "(",
              SceneAuthoredShaderTokenScanner.matchingParenthesis(tokens: tokens,
                opening: range.lowerBound + 1) == range.upperBound - 1,
              let ranges = argumentRanges(opening: range.lowerBound + 1,
                closing: range.upperBound - 1, tokens: tokens), ranges.count == count else { return nil }
        let arguments = ranges.compactMap {
            componentExpression($0, tokens: tokens, unit: unit, valueTypes: valueTypes,
                permitsScalarVectorAddition: permitsScalarVectorAddition,
                permitsVectorTruncation: permitsVectorTruncation)
        }
        guard arguments.count == count else { return nil }
        let types = arguments.map { argument -> SceneAuthoredShaderValueType in
            let first = tokens[argument.range.lowerBound]
            return argument.range.count == 1 && first.kind == .number
                ? numericLiteralType(first.text) : argument.type
        }
        guard types.contains(where: { $0 == .float || floatVectorWidth($0) != nil }),
              zip(arguments, types).allSatisfy({ argument, type in
                type == .float || floatVectorWidth(type) != nil
                    || (type == .int && argument.range.count == 1
                        && tokens[argument.range.lowerBound].kind == .number
                        && Int(tokens[argument.range.lowerBound].text) != nil)
              }) else { return nil }
        let width = types.compactMap(floatVectorWidth).min()
        let name = tokens[range.lowerBound].text
        var conversions = arguments.flatMap(\.conversions)
        for (index, pair) in zip(arguments, types).enumerated() {
            let (argument, type) = pair
            // GLSL and Metal already broadcast a scalar interpolation weight.
            let nativeScalarWeight = ["mix", "lerp"].contains(name) && index == 2 && type == .float
            if let width, (type == .float || type == .int), !nativeScalarWeight {
                conversions.append(.init(range: argument.range, operation: .broadcast(width)))
            } else if let width, let sourceWidth = floatVectorWidth(type), sourceWidth > width,
                      let suffix = narrowingSuffix(from: sourceWidth, to: width) {
                conversions.append(.init(range: argument.range, suffix: suffix))
            }
            if type == .int {
                conversions.append(.init(range: argument.range, operation: .floatingLiteral))
            }
        }
        if name == "dot", width == nil {
            conversions.append(.init(range: range, operation: .scalarDot))
        }
        return .init(range: range,
            type: name == "dot" ? .float : width.map { vectorType(width: $0) } ?? .float,
            conversions: conversions, compound: true, directlyNarrowable: false)
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
