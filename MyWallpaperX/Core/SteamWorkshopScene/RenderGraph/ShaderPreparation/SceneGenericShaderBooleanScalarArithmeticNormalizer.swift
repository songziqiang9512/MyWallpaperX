import Foundation

/// Makes the authored numeric-bool arithmetic surface explicit for Vulkan
/// GLSL without changing ordinary control-flow comparisons.
nonisolated enum SceneGenericShaderBooleanScalarArithmeticNormalizer {
    static func rewrite(_ source: String) -> String {
        let atom = #"(?:[A-Za-z_][A-Za-z0-9_]*(?:\s*\.\s*[xyzwrgba])?|[-+]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+))"#
        let pattern = #"(?<![A-Za-z0-9_])\(\s*("# + atom
            + #"\s*(?:<=|>=|==|!=|<|>)\s*"# + atom
            + #")\s*\)(?=\s*[+\-*/])"#
        let regex = try! NSRegularExpression(pattern: pattern)
        var result = regex.stringByReplacingMatches(
            in: source,
            range: NSRange(source.startIndex..., in: source),
            withTemplate: "float($1)"
        )
        let compound = try! NSRegularExpression(pattern:
            #"\b[A-Za-z_][A-Za-z0-9_]*(?:\s*(?:\.\s*[xyzwrgba]|\[[^\]\r\n]+\]))*\s*(?:\+=|-=|\*=|\/=)\s*([^;?\r\n]*(?:<=|>=|==|!=|<|>)[^;?\r\n]*)(\s*;)"#
        )
        for match in compound.matches(
            in: result,
            range: NSRange(result.startIndex..., in: result)
        ).reversed() {
            guard let range = Range(match.range(at: 1), in: result) else { continue }
            let expression = String(result[range])
            guard !expression.trimmingCharacters(in: .whitespaces)
                .hasPrefix("float(") else { continue }
            result.replaceSubrange(range, with: "float(\(expression))")
        }
        return result
    }
}
