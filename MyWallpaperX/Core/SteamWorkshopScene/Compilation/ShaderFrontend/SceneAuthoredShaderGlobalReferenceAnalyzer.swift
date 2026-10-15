import Foundation

/// Resolves references to top-level authored declarations while accounting for
/// parameters, lexical declarations and statement-scoped local variables.
nonisolated enum SceneAuthoredShaderGlobalReferenceAnalyzer {
    typealias Unit = SceneAuthoredShaderSyntaxUnit
    typealias Token = SceneAuthoredShaderToken

    private enum FunctionTask {
        case sequence(end: Int)
        case statement(end: Int, sharesScope: Bool)
        case endBlock(limit: Int, popsScope: Bool)
        case popScope
        case afterIf(end: Int)
        case afterDo(end: Int)
    }

    static func isReferenced(_ name: String, in unit: Unit) -> Bool {
        let analysis = references(to: name, in: unit)
        return !analysis.indices.isEmpty || analysis.possible
    }

    static func referenceTokens(in unit: Unit) -> Set<Token> {
        Set(unit.declarations.flatMap {
            referenceIndices($0.name, in: unit).map { unit.tokens[$0] }
        })
    }

    static func referenceIndices(_ name: String, in unit: Unit) -> [Int] {
        references(to: name, in: unit).indices
    }

    /// An empty array proves no global use. Nil means some uses could not be
    /// resolved, so a consumer must not rewrite only the known subset.
    static func exactReferenceIndices(_ name: String, in unit: Unit) -> [Int]? {
        let analysis = references(to: name, in: unit)
        return analysis.possible ? nil : analysis.indices
    }

    /// A possible use keeps the declaration live, but is not a token-resolution
    /// fact. In particular, an unrecognized binding must never turn a possible
    /// local into a context-field access in the Metal emitter.
    private static func references(
        to name: String,
        in unit: Unit
    ) -> (indices: [Int], possible: Bool) {
        let declarationRanges = unit.declarations.filter {
            $0.name == name
        }.map(\.range)
        let functionRanges = unit.functions.map {
            $0.headerRange.lowerBound..<$0.bodyRange.upperBound
        }
        var structureIndices: Set<Int> = []
        var structureReferences: [Int] = []
        var possible = false
        for index in unit.tokens.indices where unit.tokens[index].text == "struct" {
            guard !structureIndices.contains(index),
                  !functionRanges.contains(where: { $0.contains(index) }),
                  let structure = structureBody(at: index, before: unit.tokens.count, tokens: unit.tokens) else {
                continue
            }
            structureIndices.formUnion(index...structure.end)
            let members = structureMemberValues(in: structure.body, tokens: unit.tokens)
            for range in members.known {
                structureReferences.append(contentsOf: range.filter {
                    unit.tokens[$0].text == name && ($0 == 0 || unit.tokens[$0 - 1].text != ".")
                })
            }
            possible = possible || members.unknown.contains { range in
                range.contains { unit.tokens[$0].text == name }
            }
        }
        var result = unit.tokens.indices.filter { index in
            unit.tokens[index].text == name
                && (index == 0 || unit.tokens[index - 1].text != ".")
                && !declarationRanges.contains(where: { $0.contains(index) })
                && !functionRanges.contains(where: { $0.contains(index) })
                && !structureIndices.contains(index)
        }
        result.append(contentsOf: structureReferences)
        for function in unit.functions {
            let functionReferences = references(
                to: name,
                in: function,
                unit: unit
            )
            result.append(contentsOf: functionReferences.indices)
            possible = possible || functionReferences.possible
        }
        return (result.sorted(), possible)
    }

    private static func references(
        to name: String,
        in function: Unit.Function,
        unit: Unit
    ) -> (indices: [Int], possible: Bool) {
        let tokens = unit.tokens
        let parameters = parameterNames(function, unit: unit, resolving: name)
        var scopes = [parameters.names]
        var uncertainScopes = [parameters.uncertain]
        var result: [Int] = []
        var possible = parameters.uncertain

        func close(at index: Int, before limit: Int) -> Int? {
            guard let closing = SceneAuthoredShaderSyntaxAnalyzer.matchingDelimiter(
                at: index, tokens: tokens
            ), closing < limit else { return nil }
            return closing
        }

        func isUse(_ index: Int) -> Bool {
            tokens[index].text == name
                && (index == 0 || tokens[index - 1].text != ".")
        }

        func read(_ range: Range<Int>) {
            guard !scopes.contains(where: { $0.contains(name) }) else { return }
            for index in range where isUse(index) {
                if uncertainScopes.contains(true) {
                    possible = true
                } else {
                    result.append(index)
                }
            }
        }

        func unknown(_ range: Range<Int>) {
            guard !scopes.contains(where: { $0.contains(name) }),
                  range.contains(where: isUse) else { return }
            possible = true
            // The unknown statement might bind this name for the rest of its
            // containing scope. Do not guess either its lifetime or its uses.
            uncertainScopes[uncertainScopes.count - 1] = true
        }

        func pushScope() {
            scopes.append([])
            uncertainScopes.append(false)
        }

        func popScope() {
            scopes.removeLast()
            uncertainScopes.removeLast()
        }

        func consume(_ bindings: [(index: Int, dimensions: Range<Int>, initializer: Range<Int>?)]) {
            for binding in bindings {
                if let initializer = binding.initializer {
                    // GLSL section 4.2: the new name is not visible in its initializer.
                    read(binding.dimensions)
                    read(initializer)
                    scopes[scopes.count - 1].insert(tokens[binding.index].text)
                } else {
                    // Without an initializer, visibility starts after the name.
                    scopes[scopes.count - 1].insert(tokens[binding.index].text)
                    read(binding.dimensions)
                }
            }
        }

        func structureDeclaration(_ range: Range<Int>, at start: Int) {
            guard let structure = structureBody(at: start, before: range.upperBound, tokens: tokens) else {
                unknown(range); return
            }
            let members = structureMemberValues(in: structure.body, tokens: tokens)
            for range in members.known { read(range) }
            for range in members.unknown { unknown(range) }
            if let nameIndex = structure.name {
                scopes[scopes.count - 1].insert(tokens[nameIndex].text)
            }
            let tail = (structure.end + 1)..<range.upperBound
            guard !tail.isEmpty else { return }
            guard let bindings = declarators(in: tail, tokens: tokens) else { unknown(tail); return }
            consume(bindings)
        }

        func declarationOrExpression(_ range: Range<Int>) {
            guard !range.isEmpty else { return }
            let type = typeIndex(in: range, tokens: tokens)
            guard type < range.upperBound else { unknown(range); return }
            if tokens[type].text == "struct" {
                structureDeclaration(range, at: type)
                return
            }
            guard SceneAuthoredShaderValueType(authoredName: tokens[type].text) != nil else {
                // A user-defined/unknown type or qualifier can declare a local,
                // whereas return and ordinary expressions cannot. Keep that
                // distinction without inventing a new type-admission route.
                if type + 1 < range.upperBound, tokens[type + 1].kind == .identifier,
                   !["return", "break", "continue", "discard"].contains(tokens[type].text) {
                    unknown(range)
                } else {
                    read(range)
                }
                return
            }
            guard let valuesStart = afterType(at: type, before: range.upperBound, tokens: tokens) else {
                unknown(range); return
            }
            guard valuesStart < range.upperBound, tokens[valuesStart].kind == .identifier else {
                // A value constructor at the start is an expression statement.
                read(range)
                return
            }
            guard let bindings = declarators(in: valuesStart..<range.upperBound, tokens: tokens) else {
                unknown(range); return
            }
            read((type + 1)..<valuesStart)
            consume(bindings)
        }

        var cursor = function.bodyRange.lowerBound + 1
        var tasks: [FunctionTask] = [.sequence(end: function.bodyRange.upperBound - 1)]
        func abandon(until limit: Int) {
            unknown(cursor..<limit)
            cursor = limit
        }
        func scheduleScopedStatement(until limit: Int) {
            pushScope()
            tasks.append(.popScope)
            tasks.append(.statement(end: limit, sharesScope: true))
        }

        // Continuations keep native stack use constant for deeply nested author
        // blocks/control flow. Task count is bounded by the existing token input;
        // no new source-depth limit changes previously resolvable references.
        while let task = tasks.popLast() {
            switch task {
            case let .sequence(end):
                if cursor < end, tokens[cursor].text != "}" {
                    tasks.append(.sequence(end: end))
                    tasks.append(.statement(end: end, sharesScope: false))
                }
            case let .endBlock(limit, popsScope):
                if popsScope { popScope() }
                if cursor < limit, tokens[cursor].text == "}" { cursor += 1 }
            case .popScope:
                popScope()
            case let .afterIf(end):
                if cursor < end, tokens[cursor].text == "else" {
                    cursor += 1
                    scheduleScopedStatement(until: end)
                }
            case let .afterDo(end):
                guard cursor + 1 < end, tokens[cursor].text == "while",
                      tokens[cursor + 1].text == "(",
                      let conditionEnd = close(at: cursor + 1, before: end),
                      conditionEnd + 1 < end, tokens[conditionEnd + 1].text == ";" else {
                    abandon(until: end); continue
                }
                // A do body's locals have expired before the while test.
                read((cursor + 2)..<conditionEnd)
                cursor = conditionEnd + 2
            case let .statement(limit, sharesScope):
                guard cursor < limit else { continue }
                if cursor + 3 < limit,
                   tokens[cursor].text == "[", tokens[cursor + 1].text == "loop",
                   tokens[cursor + 2].text == "]", tokens[cursor + 3].text == "for" {
                    // This exact authored hint is already supported by the
                    // bounded loop owner and emitter; it adds no binding.
                    cursor += 3
                }
                let start = cursor
                switch tokens[start].text {
                case "{":
                    if !sharesScope { pushScope() }
                    cursor = start + 1
                    // Delimiters are already validated by SyntaxAnalyzer.
                    // Visit this block once, stopping at its closing brace;
                    // pre-scanning each nested block would be quadratic.
                    tasks.append(.endBlock(limit: limit, popsScope: !sharesScope))
                    tasks.append(.sequence(end: limit))
                case "if":
                    guard start + 1 < limit, tokens[start + 1].text == "(",
                          let conditionEnd = close(at: start + 1, before: limit) else {
                        abandon(until: limit); continue
                    }
                    read((start + 2)..<conditionEnd)
                    cursor = conditionEnd + 1
                    tasks.append(.afterIf(end: limit))
                    scheduleScopedStatement(until: limit)
                case "for", "while":
                    guard start + 1 < limit, tokens[start + 1].text == "(",
                          let conditionEnd = close(at: start + 1, before: limit) else {
                        abandon(until: limit); continue
                    }
                    let header = (start + 2)..<conditionEnd
                    if tokens[start].text == "for" {
                        guard let clauses = parts(header, separatedBy: ";", tokens: tokens), clauses.count == 3 else {
                            abandon(until: limit); continue
                        }
                        pushScope()
                        declarationOrExpression(clauses[0])
                        declarationOrExpression(clauses[1])
                        read(clauses[2])
                    } else {
                        pushScope()
                        declarationOrExpression(header)
                    }
                    cursor = conditionEnd + 1
                    tasks.append(.popScope)
                    // The loop's substatement shares its declaration scope.
                    tasks.append(.statement(end: limit, sharesScope: true))
                case "do":
                    cursor = start + 1
                    tasks.append(.afterDo(end: limit))
                    scheduleScopedStatement(until: limit)
                case "switch":
                    guard start + 1 < limit, tokens[start + 1].text == "(",
                          let expressionEnd = close(at: start + 1, before: limit) else {
                        abandon(until: limit); continue
                    }
                    read((start + 2)..<expressionEnd)
                    cursor = expressionEnd + 1
                    scheduleScopedStatement(until: limit)
                case "case", "default":
                    cursor = start + 1
                    var conditionals = 0
                    while cursor < limit {
                        if ["(", "[", "{"].contains(tokens[cursor].text) {
                            guard let end = close(at: cursor, before: limit) else { break }
                            cursor = end + 1
                            continue
                        }
                        if tokens[cursor].text == "?" { conditionals += 1 }
                        if tokens[cursor].text == ":" {
                            if conditionals == 0 { break }
                            conditionals -= 1
                        }
                        cursor += 1
                    }
                    if cursor < limit, tokens[cursor].text == ":" {
                        read((start + 1)..<cursor)
                        cursor += 1
                    } else {
                        cursor = start
                        abandon(until: limit)
                    }
                default:
                    while cursor < limit, tokens[cursor].text != ";" {
                        if ["(", "[", "{"].contains(tokens[cursor].text) {
                            guard let end = close(at: cursor, before: limit) else { break }
                            cursor = end + 1
                        } else {
                            cursor += 1
                        }
                    }
                    if cursor < limit, tokens[cursor].text == ";" {
                        declarationOrExpression(start..<cursor)
                        cursor += 1
                    } else {
                        cursor = start
                        abandon(until: limit)
                    }
                }
            }
        }
        return (result, possible)
    }

    // Complete existing delimiter facts include initializer lists. Separators
    // inside a call, subscript or list do not split declarations or loop clauses.
    private static func parts(
        _ range: Range<Int>, separatedBy separator: String, tokens: [Token]
    ) -> [Range<Int>]? {
        var result: [Range<Int>] = []
        var start = range.lowerBound
        var cursor = start
        while cursor < range.upperBound {
            let text = tokens[cursor].text
            if ["(", "[", "{"].contains(text) {
                guard let end = SceneAuthoredShaderSyntaxAnalyzer.matchingDelimiter(
                    at: cursor, tokens: tokens
                ), end < range.upperBound else { return nil }
                cursor = end + 1
                continue
            }
            if text == separator {
                result.append(start..<cursor)
                start = cursor + 1
            }
            cursor += 1
        }
        result.append(start..<range.upperBound)
        return result
    }

    private static func declarators(
        in range: Range<Int>, tokens: [Token]
    ) -> [(index: Int, dimensions: Range<Int>, initializer: Range<Int>?)]? {
        guard let declarators = parts(range, separatedBy: ",", tokens: tokens),
              declarators.allSatisfy({ !$0.isEmpty }) else { return nil }
        var result: [(index: Int, dimensions: Range<Int>, initializer: Range<Int>?)] = []
        for declarator in declarators {
            guard tokens[declarator.lowerBound].kind == .identifier,
                  let suffixEnd = afterType(at: declarator.lowerBound, before: declarator.upperBound, tokens: tokens) else {
                return nil
            }
            let dimensions = (declarator.lowerBound + 1)..<suffixEnd
            if suffixEnd == declarator.upperBound {
                result.append((declarator.lowerBound, dimensions, nil))
            } else if tokens[suffixEnd].text == "=", suffixEnd + 1 < declarator.upperBound {
                result.append((declarator.lowerBound, dimensions, (suffixEnd + 1)..<declarator.upperBound))
            } else {
                return nil
            }
        }
        return result
    }

    private static func typeIndex(in range: Range<Int>, tokens: [Token]) -> Int {
        var index = range.lowerBound
        while index < range.upperBound,
              ["const", "lowp", "mediump", "highp", "precise"].contains(tokens[index].text) {
            index += 1
        }
        return index
    }

    private static func afterType(at index: Int, before limit: Int, tokens: [Token]) -> Int? {
        var cursor = index + 1
        while cursor < limit, tokens[cursor].text == "[" {
            guard let end = SceneAuthoredShaderSyntaxAnalyzer.matchingDelimiter(
                at: cursor, tokens: tokens
            ), end < limit else { return nil }
            cursor = end + 1
        }
        return cursor
    }

    private static func structureBody(
        at start: Int, before limit: Int, tokens: [Token]
    ) -> (name: Int?, body: Range<Int>, end: Int)? {
        var bodyStart = start + 1
        let name: Int?
        if bodyStart < limit, tokens[bodyStart].kind == .identifier {
            name = bodyStart
            bodyStart += 1
        } else {
            name = nil
        }
        guard bodyStart < limit, tokens[bodyStart].text == "{",
              let end = SceneAuthoredShaderSyntaxAnalyzer.matchingDelimiter(
                at: bodyStart, tokens: tokens
              ), end < limit else { return nil }
        return (name, (bodyStart + 1)..<end, end)
    }

    private static func structureMemberValues(
        in body: Range<Int>, tokens: [Token]
    ) -> (known: [Range<Int>], unknown: [Range<Int>]) {
        guard let members = parts(body, separatedBy: ";", tokens: tokens) else { return ([], [body]) }
        var known: [Range<Int>] = []
        var unknown: [Range<Int>] = []
        for member in members where !member.isEmpty {
            let type = typeIndex(in: member, tokens: tokens)
            // This grammar position supplies field declarations, independently
            // of whether the backend admits their type. Field names are not
            // lexical value references; dimensions/initializers still are.
            guard type < member.upperBound, tokens[type].kind == .identifier,
                  tokens[type].text != "struct",
                  let valuesStart = afterType(at: type, before: member.upperBound, tokens: tokens),
                  let fields = declarators(in: valuesStart..<member.upperBound, tokens: tokens) else {
                unknown.append(member)
                continue
            }
            known.append((type + 1)..<valuesStart)
            for field in fields {
                known.append(field.dimensions)
                if let initializer = field.initializer { known.append(initializer) }
            }
        }
        return (known, unknown)
    }

    private static func parameterNames(
        _ function: Unit.Function,
        unit: Unit,
        resolving name: String
    ) -> (names: Set<String>, uncertain: Bool) {
        guard !function.parameterRange.isEmpty else { return ([], false) }
        let tokens = unit.tokens
        guard let parameters = SceneAuthoredShaderTokenScanner.split(
            function.parameterRange, separator: ",", tokens: tokens
        ) else { return ([], tokens[function.parameterRange].contains(where: { $0.text == name })) }
        var names: Set<String> = []
        var uncertain = false
        for parameter in parameters {
            var index = parameter.lowerBound
            while index < parameter.upperBound,
                  ["const", "in", "out", "inout", "lowp", "mediump", "highp", "precise"].contains(tokens[index].text) {
                index += 1
            }
            if index < parameter.upperBound,
               SceneAuthoredShaderValueType(authoredName: tokens[index].text) != nil,
               index + 1 < parameter.upperBound, tokens[index + 1].kind == .identifier {
                names.insert(tokens[index + 1].text)
            } else if tokens[parameter].contains(where: { $0.text == name }) {
                uncertain = true
            }
        }
        return (names, uncertain)
    }
}
