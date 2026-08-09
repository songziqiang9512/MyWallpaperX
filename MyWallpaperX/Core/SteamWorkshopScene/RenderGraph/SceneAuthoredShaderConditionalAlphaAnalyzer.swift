import Foundation

/// Proves one bounded branch merge whose two outputs preserve the alpha of a
/// single sampled color source. RGB may be generated or resampled from that
/// same slot, so the emitted boundary must expose straight color to authored
/// math and premultiply the final result again.
nonisolated enum SceneAuthoredShaderConditionalAlphaAnalyzer {
    typealias Token = SceneAuthoredShaderToken
    typealias Unit = SceneAuthoredShaderSyntaxUnit

    private struct Branches {
        let thenBody: Range<Int>
        let elseBody: Range<Int>
    }

    static func analyze(
        outputUses: [Int],
        fragment: Unit,
        main: Unit.Function
    ) -> Int? {
        let tokens = fragment.tokens
        guard outputUses.count == 2,
              !main.bodyRange.contains(where: {
                  ["return", "discard"].contains(tokens[$0].text)
              }),
              fragment.functions.allSatisfy({ !["mix", "lerp"].contains($0.name) }),
              let branches = finalRootIfElse(main: main, tokens: tokens),
              let changedOutput = uniqueOutput(in: branches.thenBody, uses: outputUses),
              let fallbackOutput = uniqueOutput(in: branches.elseBody, uses: outputUses),
              statementEndsRange(changedOutput, range: branches.thenBody, tokens: tokens),
              statementEndsRange(fallbackOutput, range: branches.elseBody, tokens: tokens),
              isRootStatement(changedOutput, in: branches.thenBody, tokens: tokens),
              isRootStatement(fallbackOutput, in: branches.elseBody, tokens: tokens),
              let changedExpression = SceneAuthoredShaderColorTransferAnalyzer
                .assignmentExpression(
                    after: changedOutput, in: tokens, body: main.bodyRange
                ),
              let fallbackExpression = SceneAuthoredShaderColorTransferAnalyzer
                .assignmentExpression(
                    after: fallbackOutput, in: tokens, body: main.bodyRange
                ),
              let changed = identifier(changedExpression),
              let source = identifier(fallbackExpression),
              changed != source,
              let sourceDefinition = vectorDefinition(
                  source, in: main.bodyRange.lowerBound..<branches.thenBody.lowerBound,
                  before: changedOutput, tokens: tokens
              ),
              SceneAuthoredShaderColorTransferAnalyzer.isUnconditionalWrite(
                  sourceDefinition, tokens: tokens, body: main.bodyRange
              ),
              let sourceInitializer = SceneAuthoredShaderColorTransferAnalyzer
                .assignmentExpression(
                    after: sourceDefinition, in: tokens, body: main.bodyRange
                ),
              let slot = SceneAuthoredShaderColorTransferAnalyzer
                .directTextureSampleSlot(sourceInitializer),
              sourceIsReadOnly(
                  source,
                  after: sourceDefinition,
                  changedOutput: changedOutput,
                  fallbackExpression: fallbackExpression,
                  tokens: tokens,
                  body: main.bodyRange
              ),
              let changedDefinition = vectorDefinition(
                  changed, in: branches.thenBody,
                  before: changedOutput, tokens: tokens
              ),
              isRootStatement(changedDefinition, in: branches.thenBody, tokens: tokens),
              samplesOnlySlot(slot, in: tokens.indices, tokens: tokens),
              let alphaWrite = finalAlphaWrite(
                  changed, in: branches.thenBody,
                  before: changedOutput, tokens: tokens
              ),
              isRootStatement(alphaWrite, in: branches.thenBody, tokens: tokens),
              let alphaExpression = SceneAuthoredShaderColorTransferAnalyzer
                .assignmentExpression(
                    after: alphaWrite + 2, in: tokens, body: main.bodyRange
              ),
              alphaExpression.endIndex + 1 == changedOutput,
              sourceAlphaUseCount(source, in: main.bodyRange, tokens: tokens) == 1,
              alphaIsSourceIdentity(
                  alphaExpression,
                  source: source,
                  changed: changed,
                  fragment: fragment
              ) else {
            return nil
        }
        return slot
    }

    private static func finalRootIfElse(
        main: Unit.Function,
        tokens: [Token]
    ) -> Branches? {
        let body = main.bodyRange
        guard body.count >= 8,
              tokens[body.lowerBound].text == "{",
              tokens[body.upperBound - 1].text == "}" else { return nil }
        var depth = 0
        var rootIfs: [Int] = []
        for index in body {
            if tokens[index].text == "if", depth == 1 { rootIfs.append(index) }
            if tokens[index].text == "{" { depth += 1 }
            if tokens[index].text == "}" { depth -= 1 }
            guard depth >= 0 else { return nil }
        }
        guard depth == 0, rootIfs.count == 1, let rootIf = rootIfs.first,
              rootIf + 1 < body.upperBound, tokens[rootIf + 1].text == "(",
              let conditionEnd = matchingClose(
                  rootIf + 1, opening: "(", closing: ")", tokens: tokens
              ),
              conditionEnd + 1 < body.upperBound,
              tokens[conditionEnd + 1].text == "{",
              let thenEnd = matchingClose(
                  conditionEnd + 1, opening: "{", closing: "}", tokens: tokens
              ),
              thenEnd + 2 < body.upperBound,
              tokens[thenEnd + 1].text == "else" else { return nil }
        let thenBody = (conditionEnd + 2)..<thenEnd
        let elseStart = thenEnd + 2
        let elseBody: Range<Int>
        let end: Int
        if tokens[elseStart].text == "{" {
            guard let elseEnd = matchingClose(
                elseStart, opening: "{", closing: "}", tokens: tokens
            ) else { return nil }
            elseBody = (elseStart + 1)..<elseEnd
            end = elseEnd + 1
        } else {
            guard let semicolon = (elseStart..<body.upperBound).first(where: {
                tokens[$0].text == ";"
            }) else { return nil }
            elseBody = elseStart..<(semicolon + 1)
            end = semicolon + 1
        }
        guard !thenBody.isEmpty, !elseBody.isEmpty,
              end == body.upperBound - 1 else { return nil }
        return .init(thenBody: thenBody, elseBody: elseBody)
    }

    private static func uniqueOutput(
        in range: Range<Int>,
        uses: [Int]
    ) -> Int? {
        let matches = uses.filter(range.contains)
        return matches.count == 1 ? matches[0] : nil
    }

    private static func statementEndsRange(
        _ output: Int,
        range: Range<Int>,
        tokens: [Token]
    ) -> Bool {
        guard output + 1 < range.upperBound, tokens[output + 1].text == "=",
              let semicolon = (output..<range.upperBound).first(where: {
                  tokens[$0].text == ";"
              }) else { return false }
        return semicolon == range.upperBound - 1
    }

    private static func isRootStatement(
        _ index: Int,
        in range: Range<Int>,
        tokens: [Token]
    ) -> Bool {
        guard range.contains(index) else { return false }
        var depth = 0
        var statementStart = range.lowerBound
        for tokenIndex in range.lowerBound..<index {
            switch tokens[tokenIndex].text {
            case "{": depth += 1
            case "}":
                depth -= 1
                if depth == 0 { statementStart = tokenIndex + 1 }
            case ";" where depth == 0: statementStart = tokenIndex + 1
            default: break
            }
            guard depth >= 0 else { return false }
        }
        let controllers: Set<String> = [
            "if", "else", "for", "while", "do", "switch", "case",
        ]
        return depth == 0 && !tokens[statementStart..<index].contains {
            $0.kind == .identifier && controllers.contains($0.text)
        }
    }

    private static func vectorDefinition(
        _ name: String,
        in range: Range<Int>,
        before boundary: Int,
        tokens: [Token]
    ) -> Int? {
        let matches = range.filter { index in
            index > range.lowerBound && index + 1 < boundary
                && tokens[index].text == name
                && ["vec4", "float4"].contains(tokens[index - 1].text)
                && tokens[index + 1].text == "="
        }
        return matches.count == 1 ? matches[0] : nil
    }

    private static func sourceIsReadOnly(
        _ source: String,
        after definition: Int,
        changedOutput: Int,
        fallbackExpression: ArraySlice<Token>,
        tokens: [Token],
        body: Range<Int>
    ) -> Bool {
        let fallbackUse = fallbackExpression.startIndex
        for use in (definition + 1)..<body.upperBound where tokens[use].text == source {
            if use == fallbackUse { continue }
            guard use + 2 < body.upperBound,
                  tokens[use + 1].text == ".",
                  ["rgb", "a"].contains(tokens[use + 2].text) else { return false }
            let next = use + 3 < body.upperBound ? tokens[use + 3].text : ""
            guard !["=", "+=", "-=", "*=", "/="].contains(next) else {
                return false
            }
        }
        return fallbackUse > changedOutput
    }

    private static func samplesOnlySlot(
        _ slot: Int,
        in range: Range<Int>,
        tokens: [Token]
    ) -> Bool {
        var count = 0
        for index in range where ["texSample2D", "texture2D"].contains(tokens[index].text) {
            guard index + 3 < range.upperBound,
                  tokens[index + 1].text == "(",
                  tokens[index + 2].text == "g_Texture\(slot)",
                  tokens[index + 3].text == "," else { return false }
            count += 1
        }
        return count > 0
    }

    private static func finalAlphaWrite(
        _ name: String,
        in range: Range<Int>,
        before boundary: Int,
        tokens: [Token]
    ) -> Int? {
        let writes = range.filter { index in
            index + 3 < boundary && tokens[index].text == name
                && tokens[index + 1].text == "."
                && tokens[index + 2].text == "a"
                && tokens[index + 3].text == "="
        }
        return writes.last
    }

    private static func sourceAlphaUseCount(
        _ name: String,
        in range: Range<Int>,
        tokens: [Token]
    ) -> Int {
        range.filter { index in
            index + 2 < range.upperBound && tokens[index].text == name
                && tokens[index + 1].text == "."
                && tokens[index + 2].text == "a"
        }.count
    }

    private static func alphaIsSourceIdentity(
        _ expression: ArraySlice<Token>,
        source: String,
        changed: String,
        fragment: Unit
    ) -> Bool {
        guard let call = call(expression),
              call.arguments.count == 3,
              texts(call.arguments[0]) == [source, ".", "a"],
              texts(call.arguments[1]) == [changed, ".", "a"],
              helperReturnsFirstParameter(call.name, fragment: fragment) else {
            return false
        }
        return true
    }

    private static func helperReturnsFirstParameter(
        _ name: String,
        fragment: Unit
    ) -> Bool {
        let matches = fragment.functions.filter { $0.name == name }
        guard matches.count == 1, let function = matches.first else { return false }
        let tokens = fragment.tokens
        let parameters = split(tokens[function.parameterRange]).compactMap(identifierName)
        guard parameters.count == 3 else { return false }
        let content = tokens[(function.bodyRange.lowerBound + 1)..<(function.bodyRange.upperBound - 1)]
        let statements = splitStatements(content)
        guard statements.count == 2,
              statements[0].count == 4,
              statements[0].first?.text == "float",
              statements[0][statements[0].startIndex + 1].kind == .identifier,
              let alias = statements[0].dropFirst().first?.text,
              texts(statements[0].dropFirst(2)) == ["=", parameters[0]],
              statements[1].first?.text == "return",
              let result = call(statements[1].dropFirst()),
              ["mix", "lerp"].contains(result.name),
              result.arguments.count == 3,
              texts(result.arguments[0]) == [parameters[0]],
              texts(result.arguments[1]) == [alias],
              texts(result.arguments[2]) == [parameters[2]] else { return false }
        return true
    }

    private static func call(
        _ expression: ArraySlice<Token>
    ) -> (name: String, arguments: [ArraySlice<Token>])? {
        guard expression.count >= 3,
              let name = expression.first?.text,
              expression.first?.kind == .identifier,
              expression[expression.index(after: expression.startIndex)].text == "(",
              expression.last?.text == ")" else { return nil }
        return (name, split(expression.dropFirst(2).dropLast()))
    }

    private static func split(_ tokens: ArraySlice<Token>) -> [ArraySlice<Token>] {
        guard !tokens.isEmpty else { return [] }
        var result: [ArraySlice<Token>] = []
        var depth = 0
        var start = tokens.startIndex
        for index in tokens.indices {
            switch tokens[index].text {
            case "(", "[": depth += 1
            case ")", "]": depth -= 1
            case "," where depth == 0:
                guard start < index else { return [] }
                result.append(tokens[start..<index])
                start = index + 1
            default: break
            }
            guard depth >= 0 else { return [] }
        }
        guard depth == 0, start < tokens.endIndex else { return [] }
        result.append(tokens[start..<tokens.endIndex])
        return result
    }

    private static func splitStatements(
        _ tokens: ArraySlice<Token>
    ) -> [ArraySlice<Token>] {
        var result: [ArraySlice<Token>] = []
        var start = tokens.startIndex
        for index in tokens.indices where tokens[index].text == ";" {
            guard start < index else { return [] }
            result.append(tokens[start..<index])
            start = index + 1
        }
        return start == tokens.endIndex ? result : []
    }

    private static func identifier(_ tokens: ArraySlice<Token>) -> String? {
        guard tokens.count == 1, tokens.first?.kind == .identifier else { return nil }
        return tokens.first?.text
    }

    private static func identifierName(_ tokens: ArraySlice<Token>) -> String? {
        tokens.last(where: { $0.kind == .identifier })?.text
    }

    private static func matchingClose(
        _ openingIndex: Int,
        opening: String,
        closing: String,
        tokens: [Token]
    ) -> Int? {
        var depth = 0
        for index in openingIndex..<tokens.count {
            if tokens[index].text == opening { depth += 1 }
            if tokens[index].text == closing {
                depth -= 1
                if depth == 0 { return index }
            }
            guard depth >= 0 else { return nil }
        }
        return nil
    }

    private static func texts(_ tokens: ArraySlice<Token>) -> [String] {
        tokens.map(\.text)
    }
}
