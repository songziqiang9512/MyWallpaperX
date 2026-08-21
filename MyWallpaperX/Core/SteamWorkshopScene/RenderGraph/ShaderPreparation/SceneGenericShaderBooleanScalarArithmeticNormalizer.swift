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
        return regex.stringByReplacingMatches(
            in: source,
            range: NSRange(source.startIndex..., in: source),
            withTemplate: "float($1)"
        )
    }
}
