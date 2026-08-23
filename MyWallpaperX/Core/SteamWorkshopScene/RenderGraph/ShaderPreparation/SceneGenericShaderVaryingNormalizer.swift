import Foundation

/// Varying-specific rewrites shared by the ordinary generic source path. The
/// strict-prefix proof itself is owned by the bounded frontend type family.
nonisolated extension SceneGenericShaderSourceNormalizer {
    static func pruneUnusedVaryingComponentAssignments(
        _ source: String,
        fragmentBody: String,
        varyings: [String: Shape]
    ) -> String {
        var result = source
        for (name, shape) in varyings.sorted(by: { $0.key < $1.key }) {
            guard shape.count == nil, let width = Int(shape.type.dropFirst(3)),
                  shape.type.hasPrefix("vec"), (2 ... 4).contains(width) else { continue }
            let used = usedComponents(of: name, width: width, in: fragmentBody)
            let regex = try! NSRegularExpression(pattern:
                #"(?m)^[ \t]*"# + NSRegularExpression.escapedPattern(for: name)
                    + #"\.([xyzwrgba]{1,4})\s*=\s*([^;]*);[ \t]*$"#
            )
            let matches = regex.matches(
                in: result,
                range: NSRange(result.startIndex..., in: result)
            ).reversed()
            for match in matches {
                let swizzle = capture(match, 1, in: result)
                let expression = capture(match, 2, in: result)
                let assigned = Set(swizzle.map(componentAlias))
                guard assigned.isDisjoint(with: used), safeDeadExpression(expression),
                      let range = Range(match.range, in: result) else { continue }
                result.removeSubrange(range)
            }
        }
        return result
    }

    private static func usedComponents(
        of name: String,
        width: Int,
        in source: String
    ) -> Set<Character> {
        let regex = try! NSRegularExpression(pattern:
            #"\b"# + NSRegularExpression.escapedPattern(for: name)
                + #"\b(?:\.([xyzwrgba]{1,4}))?"#
        )
        var used = Set<Character>()
        for match in regex.matches(
            in: source,
            range: NSRange(source.startIndex..., in: source)
        ) {
            let swizzle = capture(match, 1, in: source)
            if swizzle.isEmpty { return Set("xyzw".prefix(width)) }
            used.formUnion(swizzle.map(componentAlias))
        }
        return used
    }

    private static func safeDeadExpression(_ expression: String) -> Bool {
        guard !expression.contains("++"), !expression.contains("--") else { return false }
        let allowed = try! NSRegularExpression(pattern: #"^[A-Za-z0-9_.,()\s+\-*/]+$"#)
        guard allowed.firstMatch(
            in: expression,
            range: NSRange(expression.startIndex..., in: expression)
        )?.range.length == expression.utf16.count else { return false }
        let calls = try! NSRegularExpression(pattern: #"\b([A-Za-z_]\w*)\s*\("#)
        let constructors = Set(["float", "int", "uint", "vec2", "vec3", "vec4"])
        return calls.matches(
            in: expression,
            range: NSRange(expression.startIndex..., in: expression)
        ).allSatisfy { constructors.contains(capture($0, 1, in: expression)) }
    }
}
