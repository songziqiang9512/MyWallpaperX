import Foundation

/// Admits only runtime-bounded loops whose induction variable exclusively
/// indexes fixed-size function-parameter arrays. The emitter clamps both bound
/// uniforms to the proven array extent before the loop can execute.
nonisolated enum SceneAuthoredShaderBoundedLoopAdmission {
    struct Result {
        let iterations: Int
        let boundedUniformReferences: [SceneAuthoredShaderToken: Int]
        let constantParameterArrays: Set<String>
    }

    static func compile(
        header: Range<Int>,
        body: Range<Int>,
        tokens: [SceneAuthoredShaderToken],
        declarations: [SceneAuthoredShaderSyntaxUnit.Declaration],
        parameterArrays: [String: Int]
    ) -> Result? {
        let parts = split(range: header, separator: ";", tokens: tokens)
        guard parts.count == 3 else { return nil }
        var initialization = Array(parts[0])
        if initialization.first.map({ tokens[$0].text }) == "int" {
            initialization.removeFirst()
        }
        guard initialization.count == 6,
              tokens[initialization[1]].text == "=",
              tokens[initialization[2]].text == "int",
              tokens[initialization[3]].text == "(",
              tokens[initialization[5]].text == ")" else { return nil }
        let variable = tokens[initialization[0]].text
        let minimumUniformIndex = initialization[4]
        let minimumUniform = tokens[minimumUniformIndex].text

        let condition = Array(parts[1])
        guard condition.count == 6,
              tokens[condition[0]].text == variable,
              ["<", "<="].contains(tokens[condition[1]].text),
              tokens[condition[2]].text == "int",
              tokens[condition[3]].text == "(",
              tokens[condition[5]].text == ")" else { return nil }
        let maximumUniformIndex = condition[4]
        let maximumUniform = tokens[maximumUniformIndex].text
        guard minimumUniform != maximumUniform,
              isScalarFloatUniform(minimumUniform, declarations: declarations),
              isScalarFloatUniform(maximumUniform, declarations: declarations),
              validIncrement(parts[2], variable: variable, tokens: tokens) else {
            return nil
        }

        let variableIndices = body.filter { tokens[$0].text == variable }
        guard !variableIndices.isEmpty else { return nil }
        let arrays = variableIndices.compactMap { index -> (name: String, extent: Int)? in
            guard index >= body.lowerBound + 2,
                  index + 1 < body.upperBound,
                  tokens[index - 1].text == "[",
                  tokens[index + 1].text == "]" else { return nil }
            let name = tokens[index - 2].text
            guard let extent = parameterArrays[name] else { return nil }
            return (name, extent)
        }
        let extents = arrays.map(\.extent)
        guard arrays.count == variableIndices.count,
              Set(extents).count == 1,
              let extent = extents.first,
              (1 ... 256).contains(extent) else { return nil }
        let maximum = extent - 1
        return .init(
            iterations: extent,
            boundedUniformReferences: [
                tokens[minimumUniformIndex]: maximum,
                tokens[maximumUniformIndex]: maximum,
            ],
            constantParameterArrays: Set(arrays.map(\.name))
        )
    }

    static func parameterArrays(
        in range: Range<Int>,
        tokens: [SceneAuthoredShaderToken]
    ) -> [String: Int] {
        var result: [String: Int] = [:]
        var index = range.lowerBound
        while index + 4 < range.upperBound {
            guard tokens[index].text == "float",
                  tokens[index + 1].kind == .identifier,
                  tokens[index + 2].text == "[",
                  let extent = Int(tokens[index + 3].text),
                  extent > 0,
                  tokens[index + 4].text == "]" else {
                index += 1
                continue
            }
            result[tokens[index + 1].text] = extent
            index += 5
        }
        return result
    }

    static func mergeBounds(
        _ source: [SceneAuthoredShaderToken: Int],
        into target: inout [SceneAuthoredShaderToken: Int]
    ) -> Bool {
        for (token, maximum) in source {
            if let existing = target[token], existing != maximum { return false }
            target[token] = maximum
        }
        return true
    }

    private static func isScalarFloatUniform(
        _ name: String,
        declarations: [SceneAuthoredShaderSyntaxUnit.Declaration]
    ) -> Bool {
        declarations.contains {
            $0.storage == .uniform
                && $0.name == name
                && $0.typeName == "float"
                && $0.arraySize == nil
        }
    }

    private static func validIncrement(
        _ range: Range<Int>,
        variable: String,
        tokens: [SceneAuthoredShaderToken]
    ) -> Bool {
        let increment = Array(tokens[range].map(\.text))
        return increment == [variable, "++"] || increment == ["++", variable]
    }

    private static func split(
        range: Range<Int>,
        separator: String,
        tokens: [SceneAuthoredShaderToken]
    ) -> [Range<Int>] {
        var result: [Range<Int>] = []
        var start = range.lowerBound
        var depth = 0
        for index in range {
            if ["(", "["].contains(tokens[index].text) { depth += 1 }
            if [")", "]"].contains(tokens[index].text) { depth -= 1 }
            if depth == 0, tokens[index].text == separator {
                result.append(start..<index)
                start = index + 1
            }
        }
        result.append(start..<range.upperBound)
        return result
    }
}
