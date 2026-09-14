import Foundation

nonisolated extension SceneAuthoredShaderStraightRGBScalarAlphaAnalyzer {
    struct ScalarContext {
        let globals: [String: String]
        let locals: Set<String>
        let colorNames: Set<String>
        let colorSlot: Int
    }

    static func scalarExpression(
        _ tokens: [Token],
        context: ScalarContext
    ) -> [Int]? {
        var parser = ScalarParser(tokens: tokens, context: context)
        return parser.parse()
    }

    static func safeCoordinate(
        _ tokens: [Token],
        globals: [String: String],
        locals: Set<String>
    ) -> Bool {
        guard !tokens.isEmpty, tokens.count <= 48 else { return false }
        let allowedCalls: Set<String> = ["vec2", "float2", "sin", "cos"]
        var depth = 0
        for index in tokens.indices {
            let text = tokens[index].text
            if ["=", "+=", "-=", "*=", "/=", "{", "}", ";"].contains(text) {
                return false
            }
            if text == "(" { depth += 1 }
            if text == ")" { depth -= 1 }
            guard depth >= 0, tokens[index].kind == .identifier else { continue }
            if index + 1 < tokens.count, tokens[index + 1].text == "(" {
                guard allowedCalls.contains(text) else { return false }
                continue
            }
            if index > 0, tokens[index - 1].text == "." { continue }
            guard globals[text] != "sampler2D",
                  globals[text] != nil || locals.contains(text) else { return false }
        }
        return depth == 0
    }

    static func call(
        _ tokens: [Token]
    ) -> (name: String, arguments: [[Token]])? {
        guard tokens.count >= 3,
              tokens[0].kind == .identifier,
              tokens[1].text == "(",
              matchingClose(1, tokens: tokens) == tokens.count - 1,
              let ranges = commaRanges(2..<(tokens.count - 1), tokens: tokens) else {
            return nil
        }
        return (tokens[0].text, ranges.map { Array(tokens[$0]) })
    }

    static func textureSlot(_ name: String) -> Int? {
        guard name.hasPrefix("g_Texture"),
              let slot = Int(name.dropFirst("g_Texture".count)),
              (0 ... 7).contains(slot) else { return nil }
        return slot
    }

    private struct ScalarParser {
        let tokens: [Token]
        let context: ScalarContext
        var index = 0
        var slots: [Int] = []

        mutating func parse() -> [Int]? {
            guard addition(), index == tokens.count else { return nil }
            return slots
        }

        private mutating func addition() -> Bool {
            guard multiplication() else { return false }
            while index < tokens.count, ["+", "-"].contains(tokens[index].text) {
                index += 1
                guard multiplication() else { return false }
            }
            return true
        }

        private mutating func multiplication() -> Bool {
            guard unary() else { return false }
            while index < tokens.count, ["*", "/"].contains(tokens[index].text) {
                let operation = tokens[index].text
                index += 1
                if operation == "/" {
                    guard index < tokens.count, tokens[index].kind == .number,
                          Double(tokens[index].text).map({ $0.isFinite && $0 > 0 }) == true
                    else { return false }
                }
                guard unary() else { return false }
            }
            return true
        }

        private mutating func unary() -> Bool {
            if index < tokens.count, ["+", "-"].contains(tokens[index].text) {
                index += 1
                return unary()
            }
            return primary()
        }

        private mutating func primary() -> Bool {
            guard index < tokens.count else { return false }
            if tokens[index].text == "(" {
                index += 1
                guard addition(), index < tokens.count, tokens[index].text == ")" else {
                    return false
                }
                index += 1
                return true
            }
            if tokens[index].kind == .number {
                index += 1
                return true
            }
            guard tokens[index].kind == .identifier else { return false }
            let name = tokens[index].text
            if index + 1 < tokens.count, tokens[index + 1].text == "(" {
                return function(name)
            }
            guard !context.colorNames.contains(name),
                  let type = context.globals[name]
                    ?? (context.locals.contains(name) ? "float" : nil) else {
                return false
            }
            index += 1
            if ["float", "int", "uint", "bool"].contains(type) { return true }
            guard index + 1 < tokens.count,
                  tokens[index].text == ".",
                  tokens[index + 1].kind == .identifier,
                  tokens[index + 1].text.count == 1 else { return false }
            index += 2
            return true
        }

        private mutating func function(_ name: String) -> Bool {
            guard let close = matchingClose(index + 1, tokens: tokens),
                  let ranges = commaRanges((index + 2)..<close, tokens: tokens) else {
                return false
            }
            if ["texSample2D", "texture2D"].contains(name) {
                guard ranges.count == 2,
                      ranges[0].count == 1,
                      let slot = textureSlot(tokens[ranges[0].lowerBound].text),
                      slot != context.colorSlot,
                      safeCoordinate(
                          Array(tokens[ranges[1]]),
                          globals: context.globals,
                          locals: context.locals
                      ), close + 2 < tokens.count,
                      tokens[close + 1].text == ".",
                      tokens[close + 2].text == "r" else { return false }
                slots.append(slot)
                index = close + 3
                return true
            }
            let arity = ["sin": 1, "pow": 2, "smoothstep": 3][name]
            guard arity == ranges.count else { return false }
            for range in ranges {
                guard let nested = scalarExpression(
                    Array(tokens[range]), context: context
                ) else { return false }
                slots.append(contentsOf: nested)
            }
            index = close + 1
            return true
        }
    }

    private static func matchingClose(_ open: Int, tokens: [Token]) -> Int? {
        var depth = 0
        for index in open..<tokens.count {
            if tokens[index].text == "(" { depth += 1 }
            if tokens[index].text == ")" {
                depth -= 1
                if depth == 0 { return index }
            }
            guard depth >= 0 else { return nil }
        }
        return nil
    }

    private static func commaRanges(
        _ range: Range<Int>,
        tokens: [Token]
    ) -> [Range<Int>]? {
        guard !range.isEmpty else { return [] }
        var result: [Range<Int>] = []
        var start = range.lowerBound
        var depth = 0
        for index in range {
            if tokens[index].text == "(" { depth += 1 }
            if tokens[index].text == ")" { depth -= 1 }
            if tokens[index].text == ",", depth == 0 {
                guard start < index else { return nil }
                result.append(start..<index)
                start = index + 1
            }
            guard depth >= 0 else { return nil }
        }
        guard depth == 0, start < range.upperBound else { return nil }
        result.append(start..<range.upperBound)
        return result
    }
}
