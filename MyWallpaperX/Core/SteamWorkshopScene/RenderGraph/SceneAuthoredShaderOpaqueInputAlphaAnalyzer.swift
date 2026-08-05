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
              let colorName = outputColorName(expression) else {
            return nil
        }
        return sourceSlot(
            colorName,
            before: output,
            tokens: tokens,
            body: main.bodyRange,
            visited: []
        )
    }

    private static func outputColorName(
        _ expression: ArraySlice<SceneAuthoredShaderToken>
    ) -> String? {
        let values = Array(expression)
        if values.count == 1, values[0].kind == .identifier {
            return values[0].text
        }
        guard values.count == 4,
              values[0].text == "saturate",
              values[1].text == "(",
              values[2].kind == .identifier,
              values[3].text == ")" else {
            return nil
        }
        return values[2].text
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
            guard isAliasInitializer else { return false }
        }
        return true
    }
}
