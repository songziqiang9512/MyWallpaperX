import Foundation

/// Conserves the compiler shape for a source-proven RGB blend whose alpha is
/// attenuated by the same scalar. Only the sampled color crosses the straight
/// color boundary; auxiliary scalar textures remain data.
nonisolated enum SceneGenericShaderRGBBlendScalarAlphaLowering {
    private static let unpremultiply = "mwxGenericUnpremultiply"
    private static let premultiply = "mwxGenericPremultiply"

    static func lower(
        _ source: String,
        fact: SceneAuthoredShaderRGBBlendScalarAlphaAnalyzer.Fact
    ) -> String? {
        guard (0 ..< 8).contains(fact.sourceSlot),
              fact.auxiliarySlots.allSatisfy({ (0 ..< 8).contains($0) }),
              !fact.auxiliarySlots.contains(fact.sourceSlot),
              !containsWord(unpremultiply, in: source),
              !containsWord(premultiply, in: source),
              matches(#"\busing\s+namespace\s+metal\s*;"#, in: source).count == 1,
              let body = fragmentBodyRange(in: source),
              compilerBodyIsLinear(body, source: source)
        else { return nil }

        let expectedSlots = fact.auxiliarySlots.union([fact.sourceSlot])
        guard let sampleCalls = SceneGenericShaderStraightAlphaPreservingLowering
            .compilerTextureSampleCalls(in: source),
              sampleCalls.count == expectedSlots.count,
              Set(sampleCalls.map(\.slot)) == expectedSlots,
              expectedSlots.allSatisfy({ slot in
                  sampleCalls.filter({ $0.slot == slot }).count == 1
              }),
              sampleCalls.allSatisfy({ contains(body, $0.range) })
        else { return nil }

        let carrierDeclarations = matches(
            #"(?m)^([ \t]*float4\s+([A-Za-z_]\w*)\s*=\s*)g_Texture"#
                + String(fact.sourceSlot)
                + #"\.sample\(([^;]+)\)(\s*;[ \t]*)$"#,
            in: source
        )
        guard carrierDeclarations.count == 1,
              let carrierDeclaration = carrierDeclarations.first,
              contains(body, carrierDeclaration.range),
              let carrier = capture(carrierDeclaration, 2, in: source),
              countWord(carrier, in: source) == 2
        else { return nil }

        let aliases = matches(
            #"(?m)^[ \t]*float4\s+([A-Za-z_]\w*)\s*=\s*"#
                + escaped(carrier) + #"\s*;[ \t]*$"#,
            in: source
        )
        guard aliases.count == 1,
              let aliasDeclaration = aliases.first,
              contains(body, aliasDeclaration.range),
              let color = capture(aliasDeclaration, 1, in: source),
              color != carrier,
              carrierDeclaration.range.location < aliasDeclaration.range.location
        else { return nil }

        let blendWrites = [
            directBlendWrite(source: source, carrier: color, fact: fact),
            scalarizedBlendWrite(source: source, carrier: color, fact: fact),
        ].compactMap { $0 }
        guard blendWrites.count == 1,
              let blendWrite = blendWrites.first,
              contains(body, blendWrite.anchorRange)
        else { return nil }

        let alphaWrites = matches(
            #"(?m)^[ \t]*"# + escaped(color)
                + #"\.(?:w|a)\s*\*=\s*([A-Za-z_]\w*)\s*;[ \t]*$"#,
            in: source
        )
        let colorWrites = matches(
            #"(?m)^[ \t]*"# + escaped(color)
                + #"(?:\.([xyzwrgba]{1,4}))?\s*(?:[+\-*/]=|=(?!=))"#,
            in: source
        )
        guard alphaWrites.count == 1,
              let alphaWrite = alphaWrites.first,
              capture(alphaWrite, 1, in: source) == blendWrite.scalar,
              blendWrite.scalar == fact.factorName,
              compilerScalarDependencySlots(
                factor: blendWrite.scalar,
                before: blendWrite.anchorRange.location,
                source: source,
                auxiliarySlots: fact.auxiliarySlots
              ) == fact.auxiliarySlots,
              colorWrites.count == blendWrite.colorWriteRanges.count + 1,
              colorWrites.allSatisfy({ colorWrite in
                  blendWrite.colorWriteRanges.contains(where: { allowedRange in
                      contains(allowedRange, colorWrite.range)
                  }) || contains(alphaWrite.range, colorWrite.range)
              }),
              matches(#"(?:\+\+|--)\s*\b"# + escaped(color) + #"\b"#, in: source)
                .isEmpty,
              matches(#"\b"# + escaped(color) + #"\b\s*(?:\+\+|--)"#, in: source)
                .isEmpty
        else { return nil }

        let outputPatterns = [
            #"(?m)^([ \t]*)out\.mwxFragColor\s*=\s*(float4\(\s*fast::max\(\s*float3\(\s*0(?:\.0+)?\s*\)\s*,\s*([A-Za-z_]\w*)\.(?:xyz|rgb)\s*\)\s*,\s*([A-Za-z_]\w*)\.(?:w|a)\s*\))\s*;[ \t]*$"#,
            #"(?m)^([ \t]*)out\.mwxFragColor\s*=\s*(float4\(\s*fast::max\(\s*([A-Za-z_]\w*)\.(?:xyz|rgb)\s*,\s*float3\(\s*0(?:\.0+)?\s*\)\s*\)\s*,\s*([A-Za-z_]\w*)\.(?:w|a)\s*\))\s*;[ \t]*$"#,
        ]
        let outputs = outputPatterns.flatMap { matches($0, in: source) }
        guard outputs.count == 1,
              let output = outputs.first,
              contains(body, output.range),
              let outputRange = Range(output.range, in: source),
              let indent = capture(output, 1, in: source),
              let outputValue = capture(output, 2, in: source),
              capture(output, 3, in: source) == color,
              capture(output, 4, in: source) == color,
              countWord(color, in: source) == blendWrite.carrierWordCount,
              matches(#"\bout\.mwxFragColor\b"#, in: source).count == 1,
              carrierDeclaration.range.location < aliasDeclaration.range.location,
              aliasDeclaration.range.location < blendWrite.anchorRange.location,
              blendWrite.colorWriteRanges.allSatisfy({
                  $0.location < alphaWrite.range.location
              }),
              alphaWrite.range.location < output.range.location,
              sampleCalls.allSatisfy({ $0.range.location < output.range.location }),
              terminalTail(after: output.range, within: body, source: source)
        else { return nil }

        var transformed = source
        transformed.replaceSubrange(
            outputRange,
            with: "\(indent)out.mwxFragColor = \(premultiply)(\(outputValue));"
        )
        guard let prefix = capture(carrierDeclaration, 1, in: source),
              let sampleArguments = capture(carrierDeclaration, 3, in: source),
              let suffix = capture(carrierDeclaration, 4, in: source),
              let carrierRange = Range(carrierDeclaration.range, in: transformed)
        else { return nil }
        transformed.replaceSubrange(
            carrierRange,
            with: "\(prefix)\(unpremultiply)(g_Texture\(fact.sourceSlot).sample(\(sampleArguments)))\(suffix)"
        )
        return SceneGenericShaderStraightAlphaPreservingLowering
            .insertingBoundaryHelpers(into: transformed)
    }

    private struct BlendWrite {
        let anchorRange: NSRange
        let colorWriteRanges: [NSRange]
        let scalar: String
        let carrierWordCount: Int
    }

    private struct ParameterDeclaration {
        let range: NSRange
        let expression: String
    }

    private static func directBlendWrite(
        source: String,
        carrier: String,
        fact: SceneAuthoredShaderRGBBlendScalarAlphaAnalyzer.Fact
    ) -> BlendWrite? {
        let writes = matches(
            #"(?ms)^([ \t]*)"# + escaped(carrier)
                + #"\.(?:xyz|rgb)\s*=\s*ApplyBlending\s*\((.*?)\)\s*;[ \t]*$"#,
            in: source
        )
        guard writes.count == 1,
              let write = writes.first,
              let argumentsText = capture(write, 2, in: source),
              let arguments = splitArguments(argumentsText),
              arguments.count == 4,
              blendMode(arguments[0], expected: fact.blendMode),
              rgbBlendArgument(
                arguments[1], carrier: carrier,
                multiplier: fact.baseMultiplier
              ),
              rgbBlendArgument(
                arguments[2], carrier: carrier,
                multiplier: fact.blendMultiplier
              ),
              let scalar = scalarIdentifier(arguments[3]) else { return nil }
        return .init(
            anchorRange: write.range,
            colorWriteRanges: [write.range],
            scalar: scalar,
            carrierWordCount: 7
        )
    }

    /// SPIRV-Cross scalarizes an assigned vec3 return into one temporary and
    /// three component writes. The parameter declarations remain part of the
    /// same source-proven blend and are revalidated before accepting the form.
    private static func scalarizedBlendWrite(
        source: String,
        carrier: String,
        fact: SceneAuthoredShaderRGBBlendScalarAlphaAnalyzer.Fact
    ) -> BlendWrite? {
        let calls = matches(
            #"(?m)^[ \t]*float3\s+([A-Za-z_]\w*)\s*=\s*ApplyBlending\s*\((.*?)\)\s*;[ \t]*$"#,
            in: source
        )
        guard calls.count == 1,
              let call = calls.first,
              let result = capture(call, 1, in: source),
              let argumentsText = capture(call, 2, in: source),
              let arguments = splitArguments(argumentsText),
              arguments.count == 4,
              blendMode(arguments[0], expected: fact.blendMode),
              let leftName = scalarIdentifier(arguments[1]),
              let rightName = scalarIdentifier(arguments[2]),
              let scalarName = scalarIdentifier(arguments[3]),
              Set([result, leftName, rightName, scalarName]).count == 4,
              let left = parameterDeclaration(
                type: "float3", name: leftName, source: source
              ), let right = parameterDeclaration(
                type: "float3", name: rightName, source: source
              ), let scalar = parameterDeclaration(
                type: "float", name: scalarName, source: source
              ), let factor = scalarIdentifier(scalar.expression),
              rgbBlendArgument(
                left.expression, carrier: carrier,
                multiplier: fact.baseMultiplier
              ),
              rgbBlendArgument(
                right.expression, carrier: carrier,
                multiplier: fact.blendMultiplier
              ),
              left.range.location < right.range.location,
              right.range.location < scalar.range.location,
              scalar.range.location < call.range.location,
              countWord(leftName, in: source) == 2,
              countWord(rightName, in: source) == 2,
              countWord(scalarName, in: source) == 2,
              countWord(result, in: source) == 4 else { return nil }

        var componentWrites: [NSRange] = []
        for component in ["x", "y", "z"] {
            let writes = matches(
                #"(?m)^[ \t]*"# + escaped(carrier) + #"\."# + component
                    + #"\s*=\s*"# + escaped(result) + #"\."# + component
                    + #"\s*;[ \t]*$"#,
                in: source
            )
            guard writes.count == 1, let write = writes.first,
                  (componentWrites.last?.location ?? call.range.location)
                    < write.range.location else { return nil }
            componentWrites.append(write.range)
        }
        return .init(
            anchorRange: call.range,
            colorWriteRanges: componentWrites,
            scalar: factor,
            carrierWordCount: 9
        )
    }

    private static func parameterDeclaration(
        type: String,
        name: String,
        source: String
    ) -> ParameterDeclaration? {
        let declarations = matches(
            #"(?m)^[ \t]*"# + escaped(type) + #"\s+"# + escaped(name)
                + #"\s*=\s*(.+?)\s*;[ \t]*$"#,
            in: source
        )
        guard declarations.count == 1,
              let declaration = declarations.first,
              let expression = capture(declaration, 1, in: source) else { return nil }
        return .init(range: declaration.range, expression: expression)
    }

    private static func blendMode(_ source: String, expected: Int) -> Bool {
        let value = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let mode = Int(value) else { return false }
        return mode == expected
    }

    private static func compilerScalarDependencySlots(
        factor: String,
        before end: Int,
        source: String,
        auxiliarySlots: Set<Int>
    ) -> Set<Int>? {
        guard end >= 0, end <= (source as NSString).length else { return nil }
        let prefix = (source as NSString).substring(
            with: NSRange(location: 0, length: end)
        )
        let statements = matches(
            #"(?m)^[ \t]*(?:(float)\s+)?([A-Za-z_]\w*)\s*(=|\+=)\s*(.+?)\s*;[ \t]*$"#,
            in: prefix
        )
        var dependencies: [String: Set<Int>] = [:]
        for statement in statements {
            let declaration = capture(statement, 1, in: prefix) != nil
            guard let name = capture(statement, 2, in: prefix),
                  let operation = capture(statement, 3, in: prefix),
                  let expression = capture(statement, 4, in: prefix)
            else { return nil }
            if declaration {
                guard dependencies[name] == nil else { return nil }
                dependencies[name] = []
            } else if dependencies[name] == nil {
                continue
            }

            var expressionDependencies = Set<Int>()
            for (local, slots) in dependencies
            where containsWord(local, in: expression) {
                expressionDependencies.formUnion(slots)
            }
            let samples = matches(#"\bg_Texture([0-7])\.sample\s*\("#, in: expression)
            for sample in samples {
                guard let rawSlot = capture(sample, 1, in: expression),
                      let slot = Int(rawSlot),
                      auxiliarySlots.contains(slot) else { return nil }
                expressionDependencies.insert(slot)
            }
            if operation == "+=" {
                expressionDependencies.formUnion(dependencies[name] ?? [])
            }
            dependencies[name] = expressionDependencies
        }
        return dependencies[factor]
    }

    private static func fragmentBodyRange(in source: String) -> NSRange? {
        let signatures = matches(
            #"\bfragment\b[^\{]*\{"#,
            in: source
        )
        guard signatures.count == 1,
              let signature = signatures.first,
              let signatureRange = Range(signature.range, in: source),
              let open = source[..<signatureRange.upperBound].lastIndex(of: "{")
        else { return nil }
        var depth = 0
        var cursor = open
        while cursor < source.endIndex {
            if source[cursor] == "{" { depth += 1 }
            if source[cursor] == "}" {
                depth -= 1
                if depth == 0 {
                    let content = source.index(after: open)..<cursor
                    return NSRange(content, in: source)
                }
                if depth < 0 { return nil }
            }
            cursor = source.index(after: cursor)
        }
        return nil
    }

    private static func compilerBodyIsLinear(
        _ body: NSRange,
        source: String
    ) -> Bool {
        let text = (source as NSString).substring(with: body)
        return matches(#"\b(?:if|else|for|while|do|switch|discard)\b"#, in: text)
            .isEmpty
            && matches(#"\breturn\b"#, in: text).count == 1
    }

    private static func terminalTail(
        after output: NSRange,
        within body: NSRange,
        source: String
    ) -> Bool {
        guard NSMaxRange(output) <= NSMaxRange(body) else { return false }
        let tail = (source as NSString).substring(with: NSRange(
            location: NSMaxRange(output),
            length: NSMaxRange(body) - NSMaxRange(output)
        ))
        return matches(#"^\s*return\s+out\s*;\s*$"#, in: tail).count == 1
    }

    private static func splitArguments(_ source: String) -> [String]? {
        var arguments: [String] = []
        var start = source.startIndex
        var cursor = start
        var depth = 0
        while cursor < source.endIndex {
            switch source[cursor] {
            case "(": depth += 1
            case ")":
                depth -= 1
                if depth < 0 { return nil }
            case "," where depth == 0:
                let argument = String(source[start..<cursor])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !argument.isEmpty else { return nil }
                arguments.append(argument)
                start = source.index(after: cursor)
            default: break
            }
            cursor = source.index(after: cursor)
        }
        guard depth == 0 else { return nil }
        let last = String(source[start...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !last.isEmpty else { return nil }
        arguments.append(last)
        return arguments
    }

    private static func scalarIdentifier(_ source: String) -> String? {
        let value = source.trimmingCharacters(in: .whitespacesAndNewlines)
        return matches(#"^[A-Za-z_]\w*$"#, in: value).count == 1 ? value : nil
    }

    private static func rgbBlendArgument(
        _ source: String,
        carrier: String,
        multiplier: String
    ) -> Bool {
        let member = escaped(carrier) + #"\.(?:xyz|rgb)"#
        let uniform = #"(?:[A-Za-z_]\w*\.)*"# + escaped(multiplier)
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        return matches(
            #"^\s*(?:"# + member + #"\s*\*\s*"# + uniform
                + #"|"# + uniform + #"\s*\*\s*"# + member + #")\s*$"#,
            in: trimmed
        ).count == 1
    }

    private static func contains(_ outer: NSRange, _ inner: NSRange) -> Bool {
        inner.location >= outer.location && NSMaxRange(inner) <= NSMaxRange(outer)
    }

    private static func containsWord(_ word: String, in source: String) -> Bool {
        !matches(#"\b"# + escaped(word) + #"\b"#, in: source).isEmpty
    }

    private static func countWord(_ word: String, in source: String) -> Int {
        matches(#"\b"# + escaped(word) + #"\b"#, in: source).count
    }

    private static func matches(
        _ pattern: String,
        in source: String
    ) -> [NSTextCheckingResult] {
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        return expression.matches(
            in: source,
            range: NSRange(source.startIndex..., in: source)
        )
    }

    private static func capture(
        _ match: NSTextCheckingResult,
        _ index: Int,
        in source: String
    ) -> String? {
        let range = match.range(at: index)
        guard range.location != NSNotFound,
              let swiftRange = Range(range, in: source) else { return nil }
        return String(source[swiftRange])
    }

    private static func escaped(_ source: String) -> String {
        NSRegularExpression.escapedPattern(for: source)
    }
}
