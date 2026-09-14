import Foundation

/// Proves a bounded local straight-color flow that preserves sampled alpha.
/// RGB may change, so premultiplied inputs require an explicit shader boundary.
nonisolated enum SceneAuthoredShaderOpaqueInputAlphaAnalyzer {
    static func analyze(
        outputUses: [Int],
        fragment: SceneAuthoredShaderSyntaxUnit,
        main: SceneAuthoredShaderSyntaxUnit.Function
    ) -> Int? {
        let tokens = fragment.tokens
        guard outputUses.count == 1,
              fragment.functions.allSatisfy({ !["mix", "lerp"].contains($0.name) }),
              let output = outputUses.first,
              output + 1 < tokens.count,
              tokens[output + 1].text == "=",
              main.bodyRange.contains(output),
              SceneAuthoredShaderColorTransferAnalyzer.isUnconditionalWrite(
                  output,
                  tokens: tokens,
                  body: main.bodyRange
              ),
              let expression = SceneAuthoredShaderColorTransferAnalyzer
                  .assignmentExpression(
                      after: output,
                      in: tokens,
                      body: main.bodyRange
                  ),
              let outputColor = outputColorName(expression) else {
            return nil
        }
        guard let slot = sourceSlot(
            outputColor.name,
            before: output,
            tokens: tokens,
            body: main.bodyRange,
            visited: []
        ) else {
            return nil
        }
        if outputColor.reconstructed,
           !textureSamplesAreScalarExceptForSource(
               slot: slot,
               before: output,
               tokens: tokens,
               body: main.bodyRange
           ) {
            return nil
        }
        return slot
    }

    private static func outputColorName(
        _ expression: ArraySlice<SceneAuthoredShaderToken>
    ) -> (name: String, reconstructed: Bool)? {
        let values = Array(expression)
        if values.count == 1, values[0].kind == .identifier {
            return (values[0].text, false)
        }
        guard values.count == 4,
              values[0].text == "saturate",
              values[1].text == "(",
              values[2].kind == .identifier,
              values[3].text == ")" else {
            return reconstructedColorName(values).map { ($0, true) }
        }
        return (values[2].text, false)
    }

    /// Accepts the bounded straight-color reconstruction used by filters that
    /// clamp RGB to non-negative values while copying the sampled alpha
    /// unchanged. The shape is structural and deliberately excludes arbitrary
    /// helper calls, alternate alpha expressions, and a second color source.
    private static func reconstructedColorName(
        _ values: [SceneAuthoredShaderToken]
    ) -> String? {
        guard let arguments = callArguments(values, names: ["vec4", "float4"]),
              arguments.count == 2,
              let alphaName = memberName(arguments[1], component: "a"),
              let rgbArguments = callArguments(
                  Array(arguments[0]),
                  names: ["max"]
              ),
              rgbArguments.count == 2 else {
            return nil
        }
        let firstIsColor = memberName(rgbArguments[0], component: "rgb") == alphaName
        let secondIsColor = memberName(rgbArguments[1], component: "rgb") == alphaName
        guard firstIsColor != secondIsColor else { return nil }
        let clamp = firstIsColor ? rgbArguments[1] : rgbArguments[0]
        return isZeroVector(clamp) ? alphaName : nil
    }

    private static func callArguments(
        _ values: [SceneAuthoredShaderToken],
        names: Set<String>
    ) -> [[SceneAuthoredShaderToken]]? {
        guard values.count >= 3,
              names.contains(values[0].text),
              values[1].text == "(",
              values.last?.text == ")" else {
            return nil
        }
        var result: [[SceneAuthoredShaderToken]] = []
        var current: [SceneAuthoredShaderToken] = []
        var depth = 0
        for token in values.dropFirst(2).dropLast() {
            switch token.text {
            case "(", "[":
                depth += 1
                current.append(token)
            case ")", "]":
                depth -= 1
                guard depth >= 0 else { return nil }
                current.append(token)
            case "," where depth == 0:
                guard !current.isEmpty else { return nil }
                result.append(current)
                current = []
            default:
                current.append(token)
            }
        }
        guard depth == 0, !current.isEmpty else { return nil }
        result.append(current)
        return result
    }

    private static func memberName(
        _ values: [SceneAuthoredShaderToken],
        component: String
    ) -> String? {
        guard values.count == 3,
              values[0].kind == .identifier,
              values[1].text == ".",
              values[2].text == component else {
            return nil
        }
        return values[0].text
    }

    private static func isZeroVector(
        _ values: [SceneAuthoredShaderToken]
    ) -> Bool {
        guard let arguments = callArguments(
            values,
            names: ["vec3", "float3", "CAST3"]
        ), arguments.count == 1, arguments[0].count == 1 else {
            return false
        }
        return ["0", "0.0"].contains(arguments[0][0].text)
    }

    /// One sampled vec4 is the straight-color source. Additional texture reads
    /// may contribute scalar masks/signals only; accepting another sampled RGB
    /// would require a second unpremultiply boundary and remains fail-closed.
    private static func textureSamplesAreScalarExceptForSource(
        slot: Int,
        before boundary: Int,
        tokens: [SceneAuthoredShaderToken],
        body: Range<Int>
    ) -> Bool {
        var nonScalarSlots: [Int] = []
        for index in body where index < boundary
            && ["texSample2D", "texture2D"].contains(tokens[index].text) {
            guard index + 1 < boundary, tokens[index + 1].text == "(",
                  let closing = matchingClose(
                      for: index + 1,
                      before: boundary,
                      tokens: tokens
                  ) else {
                return false
            }
            let scalarRead = closing + 2 < boundary
                && tokens[closing + 1].text == "."
                && ["r", "g", "b", "a", "x", "y", "z", "w"]
                    .contains(tokens[closing + 2].text)
            if scalarRead { continue }
            let expression = tokens[index...closing]
            guard let sampledSlot = SceneAuthoredShaderColorTransferAnalyzer
                .directTextureSampleSlot(expression) else {
                return false
            }
            nonScalarSlots.append(sampledSlot)
        }
        return nonScalarSlots == [slot]
    }

    private static func sourceSlot(
        _ name: String,
        before boundary: Int,
        tokens: [SceneAuthoredShaderToken],
        body: Range<Int>,
        visited: Set<String>
    ) -> Int? {
        guard visited.count < 4, !visited.contains(name) else { return nil }
        let definitions = body.filter { index in
            index > body.lowerBound && index < boundary
                && tokens[index].text == name
                && ["vec4", "float4"].contains(tokens[index - 1].text)
                && index + 1 < tokens.count
                && tokens[index + 1].text == "="
        }
        guard definitions.count == 1,
              let definition = definitions.first,
              SceneAuthoredShaderColorTransferAnalyzer.isUnconditionalWrite(
                  definition,
                  tokens: tokens,
                  body: body
              ),
              alphaIsPreserved(
                  name,
                  after: definition,
                  before: boundary,
                  tokens: tokens
              ),
              let initializer = SceneAuthoredShaderColorTransferAnalyzer
                  .assignmentExpression(
                      after: definition,
                      in: tokens,
                      body: body
                  ) else {
            return nil
        }
        if let slot = SceneAuthoredShaderColorTransferAnalyzer
            .directTextureSampleSlot(initializer) {
            return slot
        }
        guard initializer.count == 1,
              let source = initializer.first,
              source.kind == .identifier else {
            return nil
        }
        var nextVisited = visited
        nextVisited.insert(name)
        return sourceSlot(
            source.text,
            before: definition,
            tokens: tokens,
            body: body,
            visited: nextVisited
        )
    }

    private static func alphaIsPreserved(
        _ name: String,
        after definition: Int,
        before boundary: Int,
        tokens: [SceneAuthoredShaderToken]
    ) -> Bool {
        let assignmentOperators: Set<String> = ["=", "+=", "-=", "*=", "/="]
        for use in (definition + 1)..<boundary where tokens[use].text == name {
            if use + 2 < boundary, tokens[use + 1].text == "." {
                let member = tokens[use + 2].text
                guard member == "rgb" || member == "a" else { return false }
                let next = use + 3 < boundary ? tokens[use + 3].text : ""
                if member == "a", assignmentOperators.contains(next) { return false }
                continue
            }
            let isAliasInitializer = use >= 3
                && tokens[use - 1].text == "="
                && ["vec4", "float4"].contains(tokens[use - 3].text)
            guard isAliasInitializer || isPureMixRead(
                at: use,
                after: definition,
                before: boundary,
                tokens: tokens
            ) else { return false }
        }
        return true
    }

    /// A source color may be passed by value to the built-in `mix`/`lerp`.
    /// This remains an alpha-preserving read when a narrower RGB destination
    /// causes the frontend to insert a bounded vector shrink. User-defined
    /// helpers and compound arguments stay closed.
    private static func isPureMixRead(
        at use: Int,
        after lowerBound: Int,
        before upperBound: Int,
        tokens: [SceneAuthoredShaderToken]
    ) -> Bool {
        guard use > lowerBound, use + 1 < upperBound else { return false }
        var depth = 0
        var opening: Int?
        for index in stride(from: use - 1, through: lowerBound + 1, by: -1) {
            switch tokens[index].text {
            case ")", "]": depth += 1
            case "(", "[":
                if depth == 0 {
                    opening = index
                    break
                }
                depth -= 1
            default: break
            }
        }
        guard let opening, opening > lowerBound,
              ["mix", "lerp"].contains(tokens[opening - 1].text),
              let closing = matchingClose(
                  for: opening,
                  before: upperBound,
                  tokens: tokens
              ) else { return false }

        var arguments: [Range<Int>] = []
        var argumentStart = opening + 1
        depth = 0
        for index in (opening + 1)..<closing {
            switch tokens[index].text {
            case "(", "[": depth += 1
            case ")", "]": depth -= 1
            case "," where depth == 0:
                arguments.append(argumentStart..<index)
                argumentStart = index + 1
            default: break
            }
            guard depth >= 0 else { return false }
        }
        arguments.append(argumentStart..<closing)
        return arguments.count == 3
            && arguments.prefix(2).contains(where: { $0 == use..<(use + 1) })
    }

    private static func matchingClose(
        for opening: Int,
        before upperBound: Int,
        tokens: [SceneAuthoredShaderToken]
    ) -> Int? {
        var depth = 0
        for index in opening..<upperBound {
            switch tokens[index].text {
            case "(": depth += 1
            case ")":
                depth -= 1
                if depth == 0 { return index }
            default: break
            }
            guard depth >= 0 else { return nil }
        }
        return nil
    }
}
