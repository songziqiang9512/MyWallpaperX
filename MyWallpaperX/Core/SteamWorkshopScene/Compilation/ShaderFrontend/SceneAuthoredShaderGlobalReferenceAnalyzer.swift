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

    struct BindingFacts {
        var valueTypes: [Token: SceneAuthoredShaderValueType] = [:]
        var globalIndices: [String: [Int]] = [:]
        var possibleGlobals: Set<String> = []
        var structureTypeNames: Set<String> = []
    }

    private struct Binding {
        let type: SceneAuthoredShaderValueType?
    }

    static func isReferenced(_ name: String, in unit: Unit) -> Bool {
        let facts = bindings(in: unit)
        return !(facts.globalIndices[name] ?? []).isEmpty || facts.possibleGlobals.contains(name)
    }

    static func referenceTokens(in unit: Unit) -> Set<Token> {
        let facts = bindings(in: unit)
        return Set(unit.declarations.flatMap {
            (facts.globalIndices[$0.name] ?? []).map { unit.tokens[$0] }
        })
    }

    static func referenceIndices(_ name: String, in unit: Unit) -> [Int] {
        bindings(in: unit).globalIndices[name] ?? []
    }

    /// Nil retains a possible global use without inventing a resolved token.
    static func exactReferenceIndices(_ name: String, in unit: Unit) -> [Int]? {
        let facts = bindings(in: unit)
        return facts.possibleGlobals.contains(name) ? nil : facts.globalIndices[name] ?? []
    }

    static func valueType(of token: Token, in unit: Unit) -> SceneAuthoredShaderValueType? {
        bindings(in: unit).valueTypes[token]
    }

    static func structureTypeNames(in unit: Unit) -> Set<String> {
        bindings(in: unit).structureTypeNames
    }

    static func valueType(
        at index: Int, tokens: [Token], in unit: Unit
    ) -> SceneAuthoredShaderValueType? {
        guard tokens.indices.contains(index) else { return nil }
        return valueType(of: tokens[index], in: unit)
    }

    private static func bindings(in unit: Unit) -> BindingFacts {
        // Syntax builds this once. The fallback preserves manually constructed
        // units without introducing mutable/global analysis state.
        unit.bindingFacts ?? analyzeBindings(in: unit)
    }

    static func analyzeBindings(in unit: Unit) -> BindingFacts {
        let tokens = unit.tokens
        let functions = unit.functions.map { $0.headerRange.lowerBound..<$0.bodyRange.upperBound }
        var facts = BindingFacts()
        var structures: Set<Int> = []
        var structureRanges: [Range<Int>] = []
        var structureValues: [Range<Int>] = []
        var unknownStructures: [Range<Int>] = []
        for index in tokens.indices where tokens[index].text == "struct" {
            guard !structures.contains(index), !functions.contains(where: { $0.contains(index) }),
                  let structure = structureBody(at: index, before: tokens.count, tokens: tokens)
            else { continue }
            structures.formUnion(index...structure.end)
            if let name = structure.name { facts.structureTypeNames.insert(tokens[name].text) }
            structureRanges.append(index..<(structure.end + 1))
            let members = structureMemberValues(in: structure.body, tokens: tokens)
            structureValues += members.known
            unknownStructures += members.unknown
        }
        // Only the global namespace uses a name map. Local identity is resolved
        // by the same lexical walk that records global references below.
        let globalDeclarations = SceneAuthoredShaderSyntaxAnalyzer.consistentValueDeclarations(
            in: tokens, excluding: functions + structureRanges
        )
        let globalTypes = globalDeclarations.compactMapValues {
            SceneAuthoredShaderValueType(rawValue: $0.type)
        }
        let declarationRanges = Dictionary(grouping: unit.declarations, by: \.name)
            .mapValues { $0.map(\.range) }
        func readGlobal(_ index: Int) {
            guard tokens[index].kind == .identifier,
                  index == 0 || tokens[index - 1].text != "." else { return }
            let name = tokens[index].text
            if let type = globalTypes[name] { facts.valueTypes[tokens[index]] = type }
            if !(declarationRanges[name] ?? []).contains(where: { $0.contains(index) }) {
                facts.globalIndices[name, default: []].append(index)
            }
        }
        for index in tokens.indices where !functions.contains(where: { $0.contains(index) })
            && !structures.contains(index) { readGlobal(index) }
        for range in structureValues { for index in range { readGlobal(index) } }
        for range in unknownStructures {
            facts.possibleGlobals.formUnion(range.compactMap {
                tokens[$0].kind == .identifier ? tokens[$0].text : nil
            })
        }
        for function in unit.functions {
            resolve(function: function, unit: unit, globalTypes: globalTypes, facts: &facts)
        }
        facts.globalIndices = facts.globalIndices.mapValues { $0.sorted() }
        return facts
    }

    private static func resolve(
        function: Unit.Function, unit: Unit,
        globalTypes: [String: SceneAuthoredShaderValueType], facts: inout BindingFacts
    ) {
        let tokens = unit.tokens
        let parameters = parameterBindings(function, unit: unit)
        var scopes = [parameters.bindings]
        var uncertainScopes = [parameters.uncertain]
        facts.possibleGlobals.formUnion(parameters.uncertain)

        func close(at index: Int, before limit: Int) -> Int? {
            guard let closing = SceneAuthoredShaderSyntaxAnalyzer.matchingDelimiter(
                at: index, tokens: tokens
            ), closing < limit else { return nil }
            return closing
        }

        func isValue(_ index: Int) -> Bool {
            tokens[index].kind == .identifier && (index == 0 || tokens[index - 1].text != ".")
        }

        func read(_ range: Range<Int>) {
            for index in range where isValue(index) {
                let name = tokens[index].text
                var resolved = false
                for scope in scopes.indices.reversed() {
                    if uncertainScopes[scope].contains(name) {
                        if !scopes.contains(where: { $0[name] != nil }) {
                            facts.possibleGlobals.insert(name)
                        }
                        resolved = true
                        break
                    }
                    if let binding = scopes[scope][name] {
                        if let type = binding.type { facts.valueTypes[tokens[index]] = type }
                        resolved = true
                        break
                    }
                }
                if !resolved {
                    if let type = globalTypes[name] { facts.valueTypes[tokens[index]] = type }
                    facts.globalIndices[name, default: []].append(index)
                }
            }
        }

        func unknown(_ range: Range<Int>) {
            for index in range where isValue(index) {
                let name = tokens[index].text
                if !scopes.contains(where: { $0[name] != nil }) { facts.possibleGlobals.insert(name) }
                uncertainScopes[uncertainScopes.count - 1].insert(name)
            }
        }

        func pushScope() { scopes.append([:]); uncertainScopes.append([]) }
        func popScope() { scopes.removeLast(); uncertainScopes.removeLast() }

        func consume(
            _ bindings: [(index: Int, dimensions: Range<Int>, initializer: Range<Int>?)],
            type: SceneAuthoredShaderValueType? = nil
        ) {
            for binding in bindings {
                let type = binding.dimensions.isEmpty ? type : nil
                if let initializer = binding.initializer {
                    // Preserve the existing GLSL initializer visibility rule.
                    read(binding.dimensions)
                    read(initializer)
                    scopes[scopes.count - 1][tokens[binding.index].text] = Binding(type: type)
                } else {
                    scopes[scopes.count - 1][tokens[binding.index].text] = Binding(type: type)
                    read(binding.dimensions)
                }
                uncertainScopes[uncertainScopes.count - 1].remove(tokens[binding.index].text)
                if let type { facts.valueTypes[tokens[binding.index]] = type }
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
                facts.structureTypeNames.insert(tokens[nameIndex].text)
                scopes[scopes.count - 1][tokens[nameIndex].text] = Binding(type: nil)
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
            consume(bindings, type: valuesStart == type + 1
                ? SceneAuthoredShaderValueType(authoredName: tokens[type].text) : nil)
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

    private static func parameterBindings(
        _ function: Unit.Function, unit: Unit
    ) -> (bindings: [String: Binding], uncertain: Set<String>) {
        guard !function.parameterRange.isEmpty else { return ([:], []) }
        let tokens = unit.tokens
        guard let parameters = SceneAuthoredShaderTokenScanner.split(
            function.parameterRange, separator: ",", tokens: tokens
        ) else { return ([:], Set(tokens[function.parameterRange].map(\.text))) }
        var bindings: [String: Binding] = [:]
        var uncertain: Set<String> = []
        for parameter in parameters {
            var index = parameter.lowerBound
            while index < parameter.upperBound,
                  ["const", "in", "out", "inout", "lowp", "mediump", "highp", "precise"].contains(tokens[index].text) {
                index += 1
            }
            if index < parameter.upperBound,
               let type = SceneAuthoredShaderValueType(authoredName: tokens[index].text),
               index + 1 < parameter.upperBound, tokens[index + 1].kind == .identifier {
                bindings[tokens[index + 1].text] = Binding(
                    type: index + 2 == parameter.upperBound ? type : nil)
            } else {
                uncertain.formUnion(tokens[parameter].filter { $0.kind == .identifier }.map(\.text))
            }
        }
        return (bindings, uncertain)
    }
}
