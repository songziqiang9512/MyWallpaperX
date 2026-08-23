import Foundation

/// Projects only immutable material producers into stage-qualified loop-bound
/// facts. Annotation `range` and `int` fields are intentionally not inputs.
nonisolated enum SceneResolvedMaterialRuntimeLoopBoundResolver {
    typealias Template = SceneResolvedMaterialTemplate

    static func resolve(
        template: Template,
        prepared: SceneShaderPreparedProgram
    ) -> SceneAuthoredShaderRuntimeLoopBounds {
        .init(
            vertexFacts: facts(template: template, source: prepared.vertex),
            fragmentFacts: facts(template: template, source: prepared.fragment)
        )
    }

    private static func facts(
        template: Template,
        source: SceneShaderPreparedSource
    ) -> [String: SceneAuthoredShaderExactScalarFact] {
        let candidates = source.activeDeclarations.filter {
            let declaration = $0.declaration
            return declaration.kind == .uniform
                && declaration.arraySize == nil
                && declaration.type.split(whereSeparator: \.isWhitespace).last?
                    .caseInsensitiveCompare("float") == .orderedSame
        }
        var result: [String: SceneAuthoredShaderExactScalarFact] = [:]
        for declarations in Dictionary(grouping: candidates, by: {
            $0.declaration.name
        }).values {
            // Repeated active declarations are not a unique producer claim,
            // even when their current scalar bits happen to agree.
            guard declarations.count == 1, let active = declarations.first else {
                continue
            }
            let declaration = active.declaration
            guard let fact = fact(
                      template: template,
                      source: source,
                      sourcePath: active.sourcePath,
                      declaration: declaration
                  ) else { continue }
            result[declaration.name] = fact
        }
        return result
    }

    private static func fact(
        template: Template,
        source: SceneShaderPreparedSource,
        sourcePath: String,
        declaration: SceneShaderContract.Declaration
    ) -> SceneAuthoredShaderExactScalarFact? {
        let annotations = source.activeAnnotations.filter {
            $0.sourcePath == sourcePath && $0.annotation.line == declaration.line
                && !isCompileTime($0.annotation)
        }
        let materialValues = annotations.compactMap { active -> String? in
            guard case let .object(object) = active.annotation.variantValue,
                  let value = object["material"] else { return nil }
            return value.stringValue
        }
        let aliases = materialValues.compactMap(normalized)
        guard aliases.count == materialValues.count,
              Set(aliases).count <= 1 else { return nil }

        var keys: Set<String> = [declaration.name]
        if let alias = aliases.first { keys.insert(alias) }
        let producers = template.uniformDeclarations.filter { keys.contains($0.name) }
        guard producers.count == 1,
              let producer = producers.first,
              case let .staticExact(value) = producer.value,
              value.componentBitPatterns.count == 1 else { return nil }
        let encoded = Float(Double(bitPattern: value.componentBitPatterns[0]))
        let integral = encoded.rounded(.towardZero)
        guard encoded.isFinite, encoded >= 0, encoded == integral,
              let exact = Int32(exactly: Double(encoded)) else { return nil }
        return .init(
            stage: source.stage,
            uniformName: declaration.name,
            producerName: producer.name,
            value: Int(exact),
            float32BitPattern: encoded.bitPattern,
            producerValueKind: value.valueKind,
            producerBindingKeys: value.authoredBindingKeys,
            shaderBindingKeys: keys.sorted(),
            sourcePath: sourcePath,
            declarationLine: declaration.line
        )
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value, !value.isEmpty,
              value == value.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.unicodeScalars.contains(where: {
                  $0.value < 32 || $0.value == 127
              }) else { return nil }
        return value
    }

    private static func isCompileTime(
        _ annotation: SceneShaderContract.Annotation
    ) -> Bool {
        if annotation.marker?.uppercased().contains("COMBO") == true { return true }
        guard case let .object(object) = annotation.variantValue else { return false }
        return object["combo"] != nil
    }
}
