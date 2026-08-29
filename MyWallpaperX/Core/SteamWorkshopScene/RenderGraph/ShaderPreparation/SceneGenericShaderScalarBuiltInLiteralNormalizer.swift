import Foundation

/// Makes integer endpoints explicit floats for authored scalar interpolation
/// built-ins. User-defined overload names remain untouched.
nonisolated enum SceneGenericShaderScalarBuiltInLiteralNormalizer {
    static func rewrite(_ source: String) -> String {
        let definition = try! NSRegularExpression(pattern:
            #"\b(?:bool|int|uint|float|[biu]?vec[2-4])\s+(lerp|smoothstep)\s*\("#
        )
        let userDefined = Set(definition.matches(
            in: source,
            range: NSRange(source.startIndex..., in: source)
        ).compactMap { match -> String? in
            guard let range = Range(match.range(at: 1), in: source) else { return nil }
            return String(source[range])
        })
        let call = try! NSRegularExpression(pattern:
            #"\b(lerp|smoothstep)\s*\(\s*([-+]?[0-9]+)\s*,\s*([-+]?[0-9]+)\s*,"#
        )
        var result = source
        for match in call.matches(
            in: source,
            range: NSRange(source.startIndex..., in: source)
        ).reversed() {
            guard let nameRange = Range(match.range(at: 1), in: source),
                  let firstRange = Range(match.range(at: 2), in: source),
                  let secondRange = Range(match.range(at: 3), in: source),
                  let fullRange = Range(match.range, in: result) else { continue }
            let name = String(source[nameRange])
            guard !userDefined.contains(name) else { continue }
            result.replaceSubrange(
                fullRange,
                with: "\(name)(\(source[firstRange]).0, \(source[secondRange]).0,"
            )
        }
        if !userDefined.contains("lerp") {
            let lerp = try! NSRegularExpression(pattern: #"\blerp(?=\s*\()"#)
            result = lerp.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: "mix"
            )
        }
        return result
    }
}
