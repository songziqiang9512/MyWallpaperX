import Foundation

nonisolated extension SceneAuthoredShaderAssociatedOverBlendAnalyzer {
    static func overlaySampleCoordinate(
        _ expression: ArraySlice<Token>
    ) -> String? {
        let tokens = Array(stripOuterParens(expression))
        guard tokens.count >= 6,
              sampleFunctions.contains(tokens[0].text),
              tokens[1].text == "(",
              tokens.last?.text == ")" else { return nil }
        var depth = 0
        var comma: Int?
        for index in 1 ..< (tokens.count - 1) {
            switch tokens[index].text {
            case "(", "[": depth += 1
            case ")", "]": depth -= 1
            case "," where depth == 1:
                guard comma == nil else { return nil }
                comma = index
            default: break
            }
            guard depth >= 0 else { return nil }
        }
        guard let comma, comma + 1 < tokens.count - 1 else { return nil }
        let coordinate = ArraySlice(tokens[(comma + 1) ..< (tokens.count - 1)])
        let stripped = stripOuterParens(coordinate)
        return identifier(stripped) ?? stripped.first?.text
    }

    static func colorParameter(_ tokens: ArraySlice<Token>) -> String? {
        typedParameter(tokens, types: colorVectorTypes)
    }

    static func scalarParameter(_ tokens: ArraySlice<Token>) -> String? {
        typedParameter(tokens, types: ["float"])
    }

    static func vectorParameter(
        _ tokens: ArraySlice<Token>,
        types: Set<String>
    ) -> Bool {
        typedParameter(tokens, types: types) != nil
    }

    static func typedParameter(
        _ tokens: ArraySlice<Token>,
        types: Set<String>
    ) -> String? {
        let parts = Array(tokens.filter { $0.text != "in" && $0.text != "const" })
        guard parts.count >= 2,
              types.contains(parts[0].text),
              parts.last?.kind == .identifier else { return nil }
        return parts.last?.text
    }

    static func floatDeclaration(_ tokens: ArraySlice<Token>) -> String? {
        let parts = Array(tokens)
        guard parts.count >= 3,
              parts[0].text == "float",
              parts[1].kind == .identifier,
              parts[2].text == "=" else { return nil }
        return parts[1].text
    }

    static func colorDeclaration(
        _ tokens: ArraySlice<Token>,
        value: String
    ) -> String? {
        let parts = Array(tokens)
        guard parts.count == 4,
              colorVectorTypes.contains(parts[0].text),
              parts[1].kind == .identifier,
              parts[2].text == "=",
              parts[3].text == value else { return nil }
        return parts[1].text
    }

    static func vectorDeclaration(_ tokens: ArraySlice<Token>) -> String? {
        let parts = Array(tokens)
        guard parts.count >= 4,
              ["vec3", "float3"].contains(parts[0].text),
              parts[1].kind == .identifier,
              parts[2].text == "=" else { return nil }
        return parts[1].text
    }

    static func assignmentExpression(
        _ tokens: ArraySlice<Token>
    ) -> ArraySlice<Token> {
        guard let index = tokens.firstIndex(where: {
            $0.text == "=" || $0.text == "+="
        }) else { return tokens }
        return tokens[tokens.index(after: index) ..< tokens.endIndex]
    }

    static func memberAssignment(
        _ tokens: ArraySlice<Token>,
        name: String,
        components: Set<String>,
        operation: String
    ) -> Bool {
        let parts = Array(tokens)
        guard parts.count >= 5,
              parts[0].text == name,
              parts[1].text == ".",
              components.contains(parts[2].text),
              parts[3].text == operation else { return false }
        return true
    }

    static func returnIdentifier(_ tokens: ArraySlice<Token>) -> String? {
        let parts = Array(tokens)
        guard parts.count == 2,
              parts[0].text == "return",
              parts[1].kind == .identifier else { return nil }
        return parts[1].text
    }

    static func returnLiteralOne(_ tokens: ArraySlice<Token>) -> Bool {
        let parts = Array(tokens)
        guard parts.count == 2, parts[0].text == "return" else { return false }
        return isOneToken(parts[1])
    }

    static func floatUniform(_ name: String, fragment: Unit) -> Bool {
        fragment.declarations.filter {
            $0.storage == .uniform
                && $0.typeName == "float"
                && $0.arraySize == nil
                && $0.name == name
        }.count == 1
    }

    static func call(_ expression: ArraySlice<Token>) -> Call? {
        let tokens = stripOuterParens(expression)
        guard tokens.count >= 3 else { return nil }
        let nameIndex = tokens.startIndex
        let openIndex = tokens.index(after: nameIndex)
        guard tokens[nameIndex].kind == .identifier,
              tokens[openIndex].text == "(",
              tokens.last?.text == ")"
        else { return nil }
        let innerStart = tokens.index(after: openIndex)
        let innerEnd = tokens.index(before: tokens.endIndex)
        guard innerStart <= innerEnd,
              let arguments = splitTopLevel(
                  tokens[innerStart ..< innerEnd],
                  separator: ","
              )
        else { return nil }
        return Call(name: tokens[nameIndex].text, arguments: arguments)
    }

    static func splitTopLevel(
        _ tokens: ArraySlice<Token>,
        separator: String
    ) -> [ArraySlice<Token>]? {
        guard !tokens.isEmpty else { return [] }
        var arguments: [ArraySlice<Token>] = []
        var depth = 0
        var start = tokens.startIndex
        for index in tokens.indices {
            switch tokens[index].text {
            case "(", "[": depth += 1
            case ")", "]": depth -= 1
            case separator where depth == 0:
                guard start < index else { return nil }
                arguments.append(tokens[start ..< index])
                start = tokens.index(after: index)
            default: break
            }
            guard depth >= 0 else { return nil }
        }
        guard depth == 0, start < tokens.endIndex else { return nil }
        arguments.append(tokens[start ..< tokens.endIndex])
        return arguments
    }

    static func productFactors(
        _ expression: ArraySlice<Token>
    ) -> [ArraySlice<Token>] {
        splitTopLevel(stripOuterParens(expression), separator: "*") ?? []
    }

    static func topLevelSummands(
        _ expression: ArraySlice<Token>
    ) -> [ArraySlice<Token>] {
        splitTopLevel(stripOuterParens(expression), separator: "+") ?? []
    }

    static func topLevelOperator(
        _ tokens: ArraySlice<Token>,
        op: String
    ) -> ArraySlice<Token>.Index? {
        var depth = 0
        var found: ArraySlice<Token>.Index?
        for index in tokens.indices {
            switch tokens[index].text {
            case "(", "[": depth += 1
            case ")", "]": depth -= 1
            case op where depth == 0:
                guard found == nil else { return nil }
                found = index
            default: break
            }
            guard depth >= 0 else { return nil }
        }
        return depth == 0 ? found : nil
    }

    static func stripOuterParens(
        _ tokens: ArraySlice<Token>
    ) -> ArraySlice<Token> {
        var current = tokens
        while current.count >= 2,
              current.first?.text == "(",
              current.last?.text == ")",
              matchingClose(current) == current.index(before: current.endIndex)
        {
            current = current.dropFirst().dropLast()
        }
        return current
    }

    static func matchingClose(
        _ tokens: ArraySlice<Token>
    ) -> ArraySlice<Token>.Index? {
        guard tokens.first?.text == "(" else { return nil }
        var depth = 0
        for index in tokens.indices {
            switch tokens[index].text {
            case "(": depth += 1
            case ")":
                depth -= 1
                if depth == 0 { return index }
            default: break
            }
            guard depth >= 0 else { return nil }
        }
        return nil
    }

    static func identifier(_ tokens: ArraySlice<Token>) -> String? {
        let value = stripOuterParens(tokens)
        guard value.count == 1, value.first?.kind == .identifier else {
            return nil
        }
        return value.first?.text
    }

    static func member(
        _ tokens: ArraySlice<Token>,
        name: String,
        components: Set<String>
    ) -> Bool {
        let value = Array(stripOuterParens(tokens))
        return value.count == 3
            && value[0].text == name
            && value[1].text == "."
            && components.contains(value[2].text)
    }

    static func isOne(_ tokens: ArraySlice<Token>) -> Bool {
        let value = Array(stripOuterParens(tokens))
        return value.count == 1 && isOneToken(value[0])
    }

    static func isOneToken(_ token: Token) -> Bool {
        guard token.kind == .number, let value = Double(token.text) else {
            return false
        }
        return value == 1
    }

    static func isThreshold(_ tokens: ArraySlice<Token>) -> Bool {
        let value = Array(stripOuterParens(tokens))
        guard value.count == 1,
              value[0].kind == .number,
              let number = Double(value[0].text) else { return false }
        return abs(number - 0.01) < 0.0000001
    }

    static func oneMinus(
        _ expression: ArraySlice<Token>,
        name: String?
    ) -> Bool {
        let value = stripOuterParens(expression)
        guard let minus = topLevelOperator(value, op: "-"),
              isOne(value[..<minus]) else { return false }
        let rhs = value[value.index(after: minus)...]
        if let name {
            return identifier(rhs) == name
        }
        return !rhs.isEmpty
    }

    static func uniqueDefinition(
        _ name: String,
        types: Set<String>,
        before boundary: Int,
        tokens: [Token],
        body: Range<Int>
    ) -> Int? {
        let matches = body.filter { index in
            index > body.lowerBound && index + 1 < boundary
                && tokens[index].text == name
                && types.contains(tokens[index - 1].text)
                && tokens[index + 1].text == "="
        }
        guard matches.count == 1, let match = matches.first,
              SceneAuthoredShaderColorTransferAnalyzer.isUnconditionalWrite(
                  match, tokens: tokens, body: body
              ) else { return nil }
        return match
    }

    static func uniqueUntypedAssignment(
        _ name: String,
        after lowerBound: Int,
        before upperBound: Int,
        tokens: [Token],
        body: Range<Int>
    ) -> Int? {
        let typeNames: Set = [
            "vec2", "vec3", "vec4", "float", "float2", "float3", "float4",
        ]
        let matches = ((lowerBound + 1) ..< upperBound).filter { index in
            index + 1 < upperBound
                && tokens[index].text == name
                && tokens[index + 1].text == "="
                && (index == body.lowerBound
                    || !typeNames.contains(tokens[index - 1].text))
                && tokens[index - 1].text != "."
        }
        guard matches.count == 1, let match = matches.first,
              SceneAuthoredShaderColorTransferAnalyzer.isUnconditionalWrite(
                  match, tokens: tokens, body: body
              ) else { return nil }
        return match
    }

    static func exactUses(
        _ name: String,
        expected: [Int],
        after lowerBound: Int,
        before upperBound: Int,
        tokens: [Token]
    ) -> Bool {
        let actual = ((lowerBound + 1) ..< upperBound).filter {
            tokens[$0].text == name
        }
        return actual == expected.sorted()
    }

    static func rootAssignment(
        _ index: Int,
        tokens: [Token],
        body: Range<Int>
    ) -> Bool {
        index + 1 < tokens.count
            && tokens[index + 1].text == "="
            && body.contains(index)
            && SceneAuthoredShaderColorTransferAnalyzer.isUnconditionalWrite(
                index, tokens: tokens, body: body
            )
    }

    static func noControlFlow(
        _ body: Range<Int>,
        tokens: [Token],
        allowReturn: Bool
    ) -> Bool {
        var forbidden: Set = [
            "if", "else", "for", "while", "do", "switch", "case",
            "discard", "?",
        ]
        if !allowReturn { forbidden.insert("return") }
        return !body.contains { forbidden.contains(tokens[$0].text) }
    }
}
