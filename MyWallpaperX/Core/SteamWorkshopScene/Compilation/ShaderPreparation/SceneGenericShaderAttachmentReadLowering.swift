import Foundation

/// Derives a separate terminal entry only after the caller's authored same-pixel
/// proof. This owner validates compiler resource uses; it does not infer UV math.
nonisolated enum SceneGenericShaderAttachmentReadLowering {
    private typealias Token = SceneAuthoredShaderToken
    private typealias Scanner = SceneAuthoredShaderTokenScanner

    private struct Parameter {
        let tokens: Range<Int>
        let source: Range<String.Index>
    }

    private struct Sample {
        let tokens: Range<Int>
        let sampler: String
        let samplerToken: Int
    }

    static func lower(
        metalSource: String,
        fragmentFunctionName: String,
        sourceTextureName: String,
        sourceSampleCallCount: Int
    ) -> String? {
        guard sourceSampleCallCount > 0, metalSource.utf8.count <= 512 * 1_024,
              let lexicalSource = lexicalSource(metalSource) else { return nil }
        let output = SceneAuthoredShaderLexer.lex(source: lexicalSource, stage: .fragment)
        let tokens = output.tokens
        guard output.diagnostics.isEmpty, !tokens.isEmpty,
              sourceSampleCallCount <= tokens.count,
              delimitersAreBalanced(tokens),
              let ranges = sourceRanges(tokens, in: metalSource) else { return nil }
        let fragmentIndices = tokens.indices.filter { tokens[$0].text == "fragment" }
        guard fragmentIndices.count == 1, let stage = fragmentIndices.first,
              stage + 3 < tokens.count,
              tokens[stage + 1].kind == .identifier,
              tokens[stage + 2].text == fragmentFunctionName,
              tokens[stage + 3].text == "(",
              tokens.filter({ $0.text == fragmentFunctionName }).count == 1,
              let close = Scanner.matchingClose(stage + 3, tokens: tokens),
              close + 1 < tokens.count, tokens[close + 1].text == "{",
              let bodyClose = SceneAuthoredShaderSyntaxAnalyzer.matchingDelimiter(
                at: close + 1, tokens: tokens),
              let parameters = parameters(open: stage + 3, close: close,
                tokens: tokens, ranges: ranges) else { return nil }
        let body = (close + 2)..<bodyClose
        let candidates = parameters.indices.filter {
            textureName(parameters[$0].tokens, tokens: tokens, binding: 0) == sourceTextureName
        }
        guard candidates.count == 1, let sourceParameter = candidates.first,
              parameters.filter({ hasAttribute("texture", value: "0",
                in: $0.tokens, tokens: tokens) }).count == 1,
              !parameters.contains(where: { parameter in
                parameter.tokens.contains { tokens[$0].text == "color" }
              }) else { return nil }
        let sourceDeclaration = parameters[sourceParameter].tokens.lowerBound + 4
        var samples: [Sample] = []
        for index in tokens.indices where tokens[index].text == sourceTextureName {
            if index == sourceDeclaration { continue }
            guard body.contains(index), index == 0 || tokens[index - 1].text != ".",
                  let call = sample(at: index, tokens: tokens),
                  call.tokens.upperBound <= body.upperBound else { return nil }
            samples.append(call)
        }
        guard samples.count == sourceSampleCallCount,
              zip(samples, samples.dropFirst()).allSatisfy({
                $0.0.tokens.upperBound <= $0.1.tokens.lowerBound
              }) else { return nil }
        let otherSamplerUses = otherSampleSamplers(sourceTextureName: sourceTextureName,
            tokens: tokens, body: body)
        var removedParameters: Set<Int> = [sourceParameter]
        for samplerName in Set(samples.map(\.sampler)) {
            let declarations = parameters.indices.filter {
                sampler(parameters[$0].tokens, tokens: tokens) == samplerName
            }
            guard declarations.count == 1, let declaration = declarations.first else { return nil }
            let declarationIndex = parameters[declaration].tokens.lowerBound + 1
            let sourceUses = Set(samples.filter { $0.sampler == samplerName }.map(\.samplerToken))
            var shared = false
            for index in tokens.indices where tokens[index].text == samplerName {
                if index == declarationIndex || sourceUses.contains(index) { continue }
                // A sampler used by another texture remains a physical argument.
                // Other uses (including declarations/shadowing) are not proved.
                guard body.contains(index), otherSamplerUses.contains(index)
                else { return nil }
                shared = true
            }
            if !shared { removedParameters.insert(declaration) }
        }
        let identifiers = Set(tokens.filter { $0.kind == .identifier }.map(\.text))
        guard let inputName = (0...identifiers.count).lazy.map({
            $0 == 0 ? "mwxAttachmentColor" : "mwxAttachmentColor\($0)"
        }).first(where: { !identifiers.contains($0) }) else { return nil }
        let kept = parameters.indices.filter { !removedParameters.contains($0) }
            .map { String(metalSource[parameters[$0].source]) }
        let parameterSource = kept.joined(separator: ",") + (kept.isEmpty ? "" : ", ")
            + "float4 \(inputName) [[color(0)]]"
        var edits: [(NSRange, String)] = [
            (NSRange(ranges[stage + 3].upperBound..<ranges[close].lowerBound,
                in: metalSource), parameterSource)
        ]
        for call in samples {
            let lower = ranges[call.tokens.lowerBound].lowerBound
            let upper = ranges[call.tokens.upperBound - 1].upperBound
            edits.append((NSRange(lower..<upper, in: metalSource), inputName))
        }
        var result = metalSource
        for (range, replacement) in edits.sorted(by: { $0.0.location > $1.0.location }) {
            guard let swiftRange = Range(range, in: result) else { return nil }
            result.replaceSubrange(swiftRange, with: replacement)
        }
        return result
    }

    private static func parameters(
        open: Int, close: Int, tokens: [Token], ranges: [Range<String.Index>]
    ) -> [Parameter]? {
        guard let parts = Scanner.split((open + 1)..<close, separator: ",", tokens: tokens)
        else { return nil }
        return parts.enumerated().map { offset, part in
            let start = offset == 0 ? ranges[open].upperBound
                : ranges[part.lowerBound - 1].upperBound
            let end = offset == parts.count - 1 ? ranges[close].lowerBound
                : ranges[part.upperBound].lowerBound
            return Parameter(tokens: part, source: start..<end)
        }
    }

    private static func textureName(
        _ range: Range<Int>, tokens: [Token], binding: Int
    ) -> String? {
        let values = range.map { tokens[$0].text }
        guard values.count == 13,
              Array(values.prefix(4)) == ["texture2d", "<", "float", ">"],
              tokens[range.lowerBound + 4].kind == .identifier,
              Array(values.suffix(8)) == ["[", "[", "texture", "(", String(binding), ")", "]", "]"]
        else { return nil }
        return values[4]
    }

    private static func sampler(_ range: Range<Int>, tokens: [Token]) -> String? {
        let values = range.map { tokens[$0].text }
        guard values.count == 10, values[0] == "sampler",
              tokens[range.lowerBound + 1].kind == .identifier,
              Array(values[2...5]) == ["[", "[", "sampler", "("],
              let slot = Int(values[6]), (0..<8).contains(slot),
              Array(values[7...9]) == [")", "]", "]"] else { return nil }
        return values[1]
    }

    private static func hasAttribute(
        _ name: String, value: String, in range: Range<Int>, tokens: [Token]
    ) -> Bool {
        let expected = ["[", "[", name, "(", value, ")", "]", "]"]
        guard range.count >= expected.count else { return false }
        return (range.lowerBound...(range.upperBound - expected.count)).contains {
            tokens[$0..<($0 + expected.count)].map(\.text) == expected
        }
    }

    private static func sample(at start: Int, tokens: [Token]) -> Sample? {
        guard start + 3 < tokens.count, tokens[start].kind == .identifier,
              tokens[start + 1].text == ".", tokens[start + 2].text == "sample",
              tokens[start + 3].text == "(",
              let close = Scanner.matchingClose(start + 3, tokens: tokens),
              let args = Scanner.argumentRanges(in: (start + 4)..<close, tokens: tokens),
              args.count == 2,
              let first = groupedIdentifier(args[0], tokens: tokens) else { return nil }
        return Sample(tokens: start..<(close + 1), sampler: tokens[first].text,
            samplerToken: first)
    }

    private static func groupedIdentifier(_ range: Range<Int>, tokens: [Token]) -> Int? {
        var range = range
        while range.count >= 2, tokens[range.lowerBound].text == "(",
              Scanner.matchingClose(range.lowerBound, tokens: tokens) == range.upperBound - 1 {
            range = (range.lowerBound + 1)..<(range.upperBound - 1)
        }
        return range.count == 1 && tokens[range.lowerBound].kind == .identifier
            ? range.lowerBound : nil
    }

    private static func otherSampleSamplers(
        sourceTextureName: String, tokens: [Token], body: Range<Int>
    ) -> Set<Int> {
        var uses: Set<Int> = []
        for receiver in body where tokens[receiver].kind == .identifier
            && tokens[receiver].text != sourceTextureName {
            guard receiver + 3 < body.upperBound,
                  tokens[receiver + 1].text == ".", tokens[receiver + 2].text == "sample",
                  tokens[receiver + 3].text == "(",
                  let close = Scanner.matchingClose(receiver + 3, tokens: tokens),
                  close < body.upperBound,
                  let args = Scanner.argumentRanges(in: (receiver + 4)..<close, tokens: tokens),
                  args.count >= 2 else { continue }
            if let index = groupedIdentifier(args[0], tokens: tokens) { uses.insert(index) }
        }
        return uses
    }

    private static func delimitersAreBalanced(_ tokens: [Token]) -> Bool {
        let openings = ["(": ")", "[": "]", "{": "}"]
        var stack: [String] = []
        for token in tokens {
            if let closing = openings[token.text] { stack.append(closing) }
            else if [")", "]", "}"].contains(token.text) {
                guard stack.popLast() == token.text else { return false }
            }
        }
        return stack.isEmpty
    }

    /// Only compiler includes and diagnostic pragmas are non-semantic here.
    /// Keep comments/line positions so the shared lexer still owns all tokens.
    private static func lexicalSource(_ source: String) -> String? {
        var inBlock = false
        var lines: [String] = []
        for line in source.components(separatedBy: "\n") {
            let scanned = SceneShaderLexicalScanner.scan(line, inBlockComment: &inBlock)
            let visible = scanned.segments.filter { $0.kind == .code || $0.kind == .quoted }
                .map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)
            if visible.hasPrefix("#") {
                guard visible.range(of: #"^#include\s*<(?:metal_stdlib|simd/simd\.h)>\s*$"#,
                    options: .regularExpression) != nil
                    || visible.range(of: #"^#pragma\s+clang\s+diagnostic\s+ignored\s+\"-W[A-Za-z0-9_-]+\"\s*$"#,
                        options: .regularExpression) != nil else { return nil }
                lines.append(scanned.segments.map { segment in
                    if segment.kind == .code || segment.kind == .quoted {
                        return segment.text.unicodeScalars.map { $0 == "\r" ? "\r" : " " }.joined()
                    }
                    return segment.text
                }.joined())
            } else { lines.append(line) }
        }
        return lines.joined(separator: "\n")
    }

    private static func sourceRanges(_ tokens: [Token], in source: String)
        -> [Range<String.Index>]? {
        let scalars = source.unicodeScalars
        var lineStarts = [scalars.startIndex]
        var cursor = scalars.startIndex
        while cursor < scalars.endIndex {
            let value = scalars[cursor]
            cursor = scalars.index(after: cursor)
            if value == "\r" {
                if cursor < scalars.endIndex, scalars[cursor] == "\n" {
                    cursor = scalars.index(after: cursor)
                }
                lineStarts.append(cursor)
            } else if value == "\n" { lineStarts.append(cursor) }
        }
        var ranges: [Range<String.Index>] = []
        for token in tokens {
            guard token.line > 0, token.line <= lineStarts.count, token.column > 0,
                  let start = scalars.index(lineStarts[token.line - 1], offsetBy: token.column - 1,
                    limitedBy: scalars.endIndex),
                  let end = scalars.index(start, offsetBy: token.text.unicodeScalars.count,
                    limitedBy: scalars.endIndex), String(source[start..<end]) == token.text
            else { return nil }
            ranges.append(start..<end)
        }
        return ranges
    }
}
