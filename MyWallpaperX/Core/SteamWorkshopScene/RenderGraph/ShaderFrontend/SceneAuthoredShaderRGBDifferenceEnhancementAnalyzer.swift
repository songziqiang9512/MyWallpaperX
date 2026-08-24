import Foundation

/// Proves a bounded two-color RGB enhancement while carrying the source
/// sample's alpha unchanged. The proof is structural and does not inspect an
/// effect, material, path, sample, layer, or asset identity.
nonisolated enum SceneAuthoredShaderRGBDifferenceEnhancementAnalyzer {
    typealias Fact = SceneAuthoredShaderPreservedAlphaRGBFilterFact
    private typealias Token = SceneAuthoredShaderToken
    typealias Unit = SceneAuthoredShaderSyntaxUnit

    private struct Sample {
        let variable: String
        let slot: Int
        let coordinate: [String]
        let statement: Range<Int>
    }

    static func analyze(fragmentSource source: String) -> Fact? {
        let syntax = SceneAuthoredShaderSyntaxAnalyzer.analyze(
            lexerOutput: SceneAuthoredShaderLexer.lex(
                source: source,
                stage: .fragment
            ),
            stage: .fragment
        )
        guard syntax.diagnostics.isEmpty, let fragment = syntax.unit else {
            return nil
        }
        return analyze(fragment)
    }

    static func analyze(_ fragment: Unit) -> Fact? {
        guard fragment.stage == .fragment,
              fragment.functions.count == 1,
              let main = fragment.functions.only,
              main.name == "main",
              let statements = statements(in: main, tokens: fragment.tokens),
              !statements.isEmpty else { return nil }
        let tokens = fragment.tokens
        let body = (main.bodyRange.lowerBound + 1)..<(main.bodyRange.upperBound - 1)
        let forbidden: Set<String> = [
            "if", "else", "for", "while", "do", "switch", "case",
            "discard", "break", "continue", "return", "?",
        ]
        guard !body.contains(where: { forbidden.contains(tokens[$0].text) }) else {
            return nil
        }

        let sampleStatements = statements.filter { statement in
            statement.contains(where: {
                ["texSample2D", "texture2D"].contains(tokens[$0].text)
            })
        }
        guard sampleStatements.count == 2 else { return nil }
        let samples = sampleStatements.compactMap {
            sample(in: $0, tokens: tokens)
        }
        guard samples.count == 2,
              Set(samples.map(\.variable)).count == 2,
              Set(samples.map(\.slot)).count == 2,
              samples.allSatisfy({
                  samplerType(slot: $0.slot, fragment: fragment) == "sampler2D"
              }) else { return nil }

        let outputStatements = statements.filter {
            $0.contains(where: { tokens[$0].text == "gl_FragColor" })
        }
        guard outputStatements.count == 1,
              let outputStatement = outputStatements.first,
              outputStatement == statements.last,
              texts(outputStatement, tokens: tokens).count == 3 else {
            return nil
        }
        let output = texts(outputStatement, tokens: tokens)
        guard output[0] == "gl_FragColor", output[1] == "=",
              let source = samples.first(where: { $0.variable == output[2] }),
              let reference = samples.first(where: {
                  $0.variable != source.variable
              }) else { return nil }

        guard let deltaStatement = statements.first(where: {
            matchesDifference(
                $0,
                source: source.variable,
                reference: reference.variable,
                tokens: tokens
            )
        }) else { return nil }
        let delta = tokens[deltaStatement.lowerBound + 1].text

        guard let enhancementStatement = statements.first(where: {
            matchesEnhancement(
                $0,
                source: source.variable,
                delta: delta,
                tokens: tokens
            )
        }) else { return nil }
        let enhancement = tokens[enhancementStatement.lowerBound + 1].text
        let amount = tokens[enhancementStatement.upperBound - 1].text
        guard scalarAmountIsProven(amount, fragment: fragment) else { return nil }

        guard let maskStatement = statements.first(where: {
            matchesUnitScalarDeclaration($0, tokens: tokens)
        }) else { return nil }
        let mask = tokens[maskStatement.lowerBound + 1].text

        guard let mixStatement = statements.first(where: {
            matchesMix(
                $0,
                source: source.variable,
                enhancement: enhancement,
                mask: mask,
                tokens: tokens
            )
        }) else { return nil }

        guard source.statement.lowerBound < deltaStatement.lowerBound,
              reference.statement.lowerBound < deltaStatement.lowerBound,
              deltaStatement.lowerBound < enhancementStatement.lowerBound,
              enhancementStatement.lowerBound < maskStatement.lowerBound,
              maskStatement.lowerBound < mixStatement.lowerBound,
              mixStatement.lowerBound < outputStatement.lowerBound else {
            return nil
        }

        var ownedStatements: Set<Range<Int>> = [
            source.statement,
            reference.statement,
            deltaStatement,
            enhancementStatement,
            maskStatement,
            mixStatement,
            outputStatement,
        ]
        let remaining = statements.filter { !ownedStatements.contains($0) }
        guard remaining.count <= 1 else { return nil }
        if let coordinateStatement = remaining.first {
            guard matchesCoordinateAlias(
                coordinateStatement,
                reference: reference,
                fragment: fragment
            ), coordinateStatement.lowerBound < reference.statement.lowerBound else {
                return nil
            }
            ownedStatements.insert(coordinateStatement)
        }
        guard ownedStatements.count == statements.count else { return nil }

        return .init(
            sourceSlot: source.slot,
            fullColorSampleCallCounts: [source.slot: 1, reference.slot: 1],
            rgbColorSampleCallCounts: [:],
            dataSampleCallCounts: [:]
        )
    }

    private static func statements(
        in main: Unit.Function,
        tokens: [Token]
    ) -> [Range<Int>]? {
        let lower = main.bodyRange.lowerBound + 1
        let upper = main.bodyRange.upperBound - 1
        guard lower <= upper else { return nil }
        var result: [Range<Int>] = []
        var start = lower
        for index in lower..<upper {
            guard !["{", "}"].contains(tokens[index].text) else { return nil }
            guard tokens[index].text == ";" else { continue }
            guard start < index else { return nil }
            result.append(start..<index)
            start = index + 1
        }
        guard start == upper else { return nil }
        return result
    }

    private static func sample(
        in statement: Range<Int>,
        tokens: [Token]
    ) -> Sample? {
        let values = texts(statement, tokens: tokens)
        guard values.count >= 9,
              ["vec4", "float4"].contains(values[0]),
              tokens[statement.lowerBound + 1].kind == .identifier,
              values[2] == "=",
              ["texSample2D", "texture2D"].contains(values[3]),
              values[4] == "(", values.last == ")",
              let slot = textureSlot(values[5]),
              values[6] == ",",
              matchingClose(in: values, opening: 4) == values.count - 1,
              values.filter({ ["texSample2D", "texture2D"].contains($0) }).count == 1
        else { return nil }
        return .init(
            variable: values[1],
            slot: slot,
            coordinate: Array(values[7..<(values.count - 1)]),
            statement: statement
        )
    }

    private static func matchesCoordinateAlias(
        _ statement: Range<Int>,
        reference: Sample,
        fragment: Unit
    ) -> Bool {
        let value = texts(statement, tokens: fragment.tokens)
        guard value.count == 6,
              ["vec2", "float2"].contains(value[0]),
              fragment.tokens[statement.lowerBound + 1].kind == .identifier,
              value[2] == "=", value[4] == ".",
              ["xy", "zw"].contains(value[5]),
              reference.coordinate == [value[1]] else { return false }
        let varying = fragment.declarations.filter {
            $0.storage == .varying
                && $0.name == value[3]
                && ["vec4", "float4"].contains($0.typeName)
                && $0.arraySize == nil
        }
        guard varying.count == 1 else { return false }
        return fragment.tokens[statement.lowerBound..<reference.statement.upperBound]
            .filter({ $0.text == value[1] }).count == 2
    }

    private static func matchesDifference(
        _ statement: Range<Int>,
        source: String,
        reference: String,
        tokens: [Token]
    ) -> Bool {
        let value = texts(statement, tokens: tokens)
        return value.count == 10
            && ["vec3", "float3"].contains(value[0])
            && value[2] == "="
            && value[3] == source && value[4] == "."
            && ["rgb", "xyz"].contains(value[5])
            && value[6] == "-"
            && value[7] == reference && value[8] == "."
            && ["rgb", "xyz"].contains(value[9])
    }

    private static func matchesEnhancement(
        _ statement: Range<Int>,
        source: String,
        delta: String,
        tokens: [Token]
    ) -> Bool {
        let value = texts(statement, tokens: tokens)
        return value.count == 10
            && ["vec3", "float3"].contains(value[0])
            && value[2] == "="
            && value[3] == source && value[4] == "."
            && ["rgb", "xyz"].contains(value[5])
            && value[6] == "+" && value[7] == delta
            && value[8] == "*"
    }

    private static func matchesUnitScalarDeclaration(
        _ statement: Range<Int>,
        tokens: [Token]
    ) -> Bool {
        let value = texts(statement, tokens: tokens)
        return value.count == 4
            && value[0] == "float"
            && value[2] == "="
            && Double(value[3]) == 1
    }

    private static func matchesMix(
        _ statement: Range<Int>,
        source: String,
        enhancement: String,
        mask: String,
        tokens: [Token]
    ) -> Bool {
        let value = texts(statement, tokens: tokens)
        return value == [
            source, ".", "rgb", "=", "mix", "(",
            source, ".", "rgb", ",",
            enhancement, ".", "rgb", ",", mask, ")",
        ] || value == [
            source, ".", "xyz", "=", "mix", "(",
            source, ".", "xyz", ",",
            enhancement, ".", "xyz", ",", mask, ")",
        ]
    }

    private static func scalarAmountIsProven(
        _ value: String,
        fragment: Unit
    ) -> Bool {
        if let number = Double(value) { return number.isFinite }
        let matches = fragment.declarations.filter {
            $0.storage == .uniform
                && $0.typeName == "float"
                && $0.name == value
                && $0.arraySize == nil
        }
        return matches.count == 1
    }

    private static func samplerType(slot: Int, fragment: Unit) -> String? {
        let declarations = fragment.declarations.filter {
            $0.storage == .uniform && $0.name == "g_Texture\(slot)"
        }
        guard declarations.count == 1 else { return nil }
        return declarations[0].typeName
    }

    private static func textureSlot(_ value: String) -> Int? {
        guard value.hasPrefix("g_Texture"),
              let slot = Int(value.dropFirst("g_Texture".count)),
              (0..<8).contains(slot) else { return nil }
        return slot
    }

    private static func matchingClose(
        in values: [String],
        opening: Int
    ) -> Int? {
        var depth = 0
        for index in opening..<values.count {
            if values[index] == "(" { depth += 1 }
            if values[index] == ")" {
                depth -= 1
                if depth == 0 { return index }
            }
        }
        return nil
    }

    private static func texts(
        _ range: Range<Int>,
        tokens: [Token]
    ) -> [String] {
        range.map { tokens[$0].text }
    }
}

private extension Array {
    nonisolated var only: Element? { count == 1 ? self[0] : nil }
}
