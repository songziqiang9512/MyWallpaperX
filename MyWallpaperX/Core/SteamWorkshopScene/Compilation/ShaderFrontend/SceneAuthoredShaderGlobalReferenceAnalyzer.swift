import Foundation

/// Resolves references to top-level authored declarations while accounting for
/// the bounded frontend's value-type parameters and lexical local variables.
nonisolated enum SceneAuthoredShaderGlobalReferenceAnalyzer {
    typealias Unit = SceneAuthoredShaderSyntaxUnit
    typealias Token = SceneAuthoredShaderToken

    static func isReferenced(_ name: String, in unit: Unit) -> Bool {
        !referenceIndices(name, in: unit).isEmpty
    }

    static func referenceTokens(in unit: Unit) -> Set<Token> {
        Set(unit.declarations.flatMap {
            referenceIndices($0.name, in: unit).map { unit.tokens[$0] }
        })
    }

    static func referenceIndices(_ name: String, in unit: Unit) -> [Int] {
        let declarationRanges = unit.declarations.filter {
            $0.name == name
        }.map(\.range)
        let functionRanges = unit.functions.map {
            $0.headerRange.lowerBound..<$0.bodyRange.upperBound
        }
        var result = unit.tokens.indices.filter { index in
            unit.tokens[index].text == name
                && !declarationRanges.contains(where: { $0.contains(index) })
                && !functionRanges.contains(where: { $0.contains(index) })
        }
        for function in unit.functions {
            result.append(contentsOf: references(
                to: name,
                in: function,
                unit: unit
            ))
        }
        return result.sorted()
    }

    private static func references(
        to name: String,
        in function: Unit.Function,
        unit: Unit
    ) -> [Int] {
        var scopes = [parameterNames(function, unit: unit)]
        var result: [Int] = []
        var index = function.bodyRange.lowerBound + 1
        let upperBound = function.bodyRange.upperBound - 1
        while index < upperBound {
            let token = unit.tokens[index]
            if token.text == "{" {
                scopes.append([])
                index += 1
                continue
            }
            if token.text == "}" {
                if scopes.count > 1 { scopes.removeLast() }
                index += 1
                continue
            }
            if let local = localDeclaration(at: index, unit: unit) {
                scopes[scopes.count - 1].insert(local.name)
                index = local.nameIndex + 1
                continue
            }
            if token.text == name,
               !scopes.contains(where: { $0.contains(name) }),
               (index == 0 || unit.tokens[index - 1].text != ".") {
                result.append(index)
            }
            index += 1
        }
        return result
    }

    private static func parameterNames(
        _ function: Unit.Function,
        unit: Unit
    ) -> Set<String> {
        guard !function.parameterRange.isEmpty else { return [] }
        return Set(function.parameterRange.compactMap { index in
            guard unit.tokens[index].kind == .identifier,
                  index > function.parameterRange.lowerBound else { return nil }
            let previous = unit.tokens[index - 1].text
            if SceneAuthoredShaderValueType(authoredName: previous) != nil {
                return unit.tokens[index].text
            }
            guard index > function.parameterRange.lowerBound + 1,
                  ["const", "in", "out", "inout"].contains(previous),
                  SceneAuthoredShaderValueType(
                      authoredName: unit.tokens[index - 2].text
                  ) != nil else { return nil }
            return unit.tokens[index].text
        })
    }

    private static func localDeclaration(
        at index: Int,
        unit: Unit
    ) -> (name: String, nameIndex: Int)? {
        var typeIndex = index
        if unit.tokens[typeIndex].text == "const" {
            typeIndex += 1
        }
        guard typeIndex + 1 < unit.tokens.count,
              SceneAuthoredShaderValueType(
                  authoredName: unit.tokens[typeIndex].text
              ) != nil,
              unit.tokens[typeIndex + 1].kind == .identifier else {
            return nil
        }
        return (unit.tokens[typeIndex + 1].text, typeIndex + 1)
    }
}
